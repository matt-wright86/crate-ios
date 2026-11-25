/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

/* A stress test of the gap claim in Sources/Crate/JIT/CodeRegion.c, for a Mac
   (Scripts/test-code-region.sh builds and runs it). While other threads map
   small pieces of memory, it claims the code region through the path that
   walks the address space for a gap below 64 GiB, and fails if the claim
   replaced any of their memory: a thread that faults writing to a page the
   kernel had just given it, or a page whose contents are gone.

   Built with -DDEBUG=1 for CodeRegion.c's CRATE_TEST_HIGH_REGION hook, which
   makes the first offer too high, as iOS does with extended virtual
   addressing.

       race [ROUNDS]     # claims to make, 300 by default */
#include "CodeRegion.h"

#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define RACERS 4
#define PAGES 4000
#define MAGIC 0xC0FFEE1234ABCDEFULL

static atomic_bool go;
static void *pages[RACERS][PAGES];
static int counts[RACERS];

static void *racer(void *arg) {
    int id = (int)(intptr_t)arg;
    size_t page = (size_t)getpagesize();
    while (!atomic_load(&go)) {}
    for (int i = 0; i < PAGES; i++) {
        uint64_t *p = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (p == MAP_FAILED) break;
        *p = MAGIC ^ (uint64_t)p;
        pages[id][i] = p;
        counts[id] = i + 1;
    }
    return NULL;
}

/* A thread wrote to memory the kernel had just given it and faulted: say where,
   and how that address is mapped now. */
static void on_fault(int sig, siginfo_t *info, void *context) {
    (void)context;
    vm_address_t at = (vm_address_t)info->si_addr;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t basic;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &at, &size, VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&basic, &count, &object);
    char line[256];
    int n = snprintf(line, sizeof line,
                     "FAILED: signal %d writing a fresh page at %p, which is now in a mapping at 0x%lx, "
                     "protection %c%c%c: the code region replaced it\n", sig, info->si_addr, (unsigned long)at,
                     kr == KERN_SUCCESS && (basic.protection & VM_PROT_READ) ? 'r' : '-',
                     kr == KERN_SUCCESS && (basic.protection & VM_PROT_WRITE) ? 'w' : '-',
                     kr == KERN_SUCCESS && (basic.protection & VM_PROT_EXECUTE) ? 'x' : '-');
    write(1, line, (size_t)n);
    _exit(2);
}

/* Reads through the kernel, so memory that has gone doesn't crash the test. */
static bool intact(void *p) {
    uint64_t value = 0;
    vm_size_t got = 0;
    if (vm_read_overwrite(mach_task_self(), (vm_address_t)p, sizeof value, (vm_address_t)&value, &got)
        != KERN_SUCCESS) return false;
    return value == (MAGIC ^ (uint64_t)p);
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 300;
    setvbuf(stdout, NULL, _IONBF, 0);
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_sigaction = on_fault;
    action.sa_flags = SA_SIGINFO;
    sigaction(SIGBUS, &action, NULL);
    sigaction(SIGSEGV, &action, NULL);

    size_t size = 512u << 20;
    setenv("CRATE_TEST_HIGH_REGION", "1", 1);
    int lost = 0, failed = 0, low = 0;
    for (int r = 0; r < rounds; r++) {
        pthread_t threads[RACERS];
        atomic_store(&go, false);
        for (int t = 0; t < RACERS; t++) {
            counts[t] = 0;
            pthread_create(&threads[t], NULL, racer, (void *)(intptr_t)t);
        }
        atomic_store(&go, true);
        /* Into the middle of their mapping, at a different moment each round. */
        usleep(200 + (unsigned)(r % 7) * 150);
        crate_code_region region = {0};
        bool ok = crate_code_region_map(size, 256u << 20, true, &region) == CRATE_REGION_OK;
        if (!ok) failed++;
        else if ((uintptr_t)region.executable + region.size <= (64ULL << 30)) low++;
        for (int t = 0; t < RACERS; t++) pthread_join(threads[t], NULL);

        for (int t = 0; t < RACERS; t++) {
            for (int i = 0; i < counts[t]; i++) {
                if (!intact(pages[t][i])) lost++;
                else munmap(pages[t][i], (size_t)getpagesize());
            }
        }
        if (ok) munmap(region.executable, region.size);
    }
    printf("%d claims, %d below 64 GiB, %d failed; %d of the other threads' pages replaced\n",
           rounds, low, failed, lost);
    /* Every claim has to have taken the path under test, and none may have cost anyone a page. */
    return lost == 0 && failed == 0 && low == rounds ? 0 : 1;
}
