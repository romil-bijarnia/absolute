#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

// Read only a branch instruction and at most six shared-cache stub instructions
// mapped into this owned process. Never execute the private entrypoints.
static uintptr_t strip(uintptr_t value) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip((void *)value, ptrauth_key_function_pointer);
#else
    return value & UINT64_C(0x0000ffffffffffff);
#endif
}

static int64_t signed_immediate(uint32_t value, unsigned bits) {
    return (value & (UINT32_C(1) << (bits - 1)))
        ? (int64_t)value - (INT64_C(1) << bits) : (int64_t)value;
}

static int inspect(void *surface, void *iokit, const char *name, size_t offset) {
    uintptr_t function = strip((uintptr_t)dlsym(surface, name));
    uintptr_t expected = strip((uintptr_t)dlsym(iokit, "IOConnectTrap3"));
    if (!function || !expected) return 1;
    uintptr_t pc = function + offset;
    uint32_t instruction;
    memcpy(&instruction, (void *)pc, sizeof(instruction));
    if ((instruction & 0xfc000000u) != 0x94000000u) return 2;
    int64_t displacement = signed_immediate(instruction & 0x03ffffffu, 26) * 4;
    uintptr_t stub = pc + displacement;
    uintptr_t registers[32] = {0};
    int matched = stub == expected;
    for (size_t i = 0; i < 6 && !matched; i++) {
        uint32_t word;
        uintptr_t address = stub + i * 4;
        memcpy(&word, (void *)address, sizeof(word));
        unsigned rd = word & 31, rn = (word >> 5) & 31;
        if ((word & 0x9f000000u) == 0x90000000u) {
            uint32_t encoded = ((word >> 29) & 3u) | (((word >> 5) & 0x7ffffu) << 2);
            int64_t immediate = signed_immediate(encoded, 21) * 4096;
            registers[rd] = (address & ~UINT64_C(4095)) + immediate;
        } else if ((word & 0xffc00000u) == 0x91000000u && registers[rn]) {
            registers[rd] = registers[rn] + ((word >> 10) & 0xfffu);
        } else if ((word & 0xffc00000u) == 0xf9400000u && registers[rn]) {
            uintptr_t pointer;
            uintptr_t location = registers[rn] + (((word >> 10) & 0xfffu) * 8);
            memcpy(&pointer, (void *)location, sizeof(pointer));
            registers[rd] = strip(pointer);
        } else if ((word & 0xfffffc1fu) == 0xd61f0000u ||
                   (word & 0xfffffc00u) == 0xd71f0800u) {
            // BR or BRAA: only report a match for the register actually branched to.
            matched = registers[rn] == expected;
            break;
        } else {
            // Unsupported stub shape remains unresolved; do not guess a target.
            break;
        }
    }
    printf("{\"function\":\"%s\",\"callOffset\":%zu,\"targetEqualsIOConnectTrap3\":%s}",
           name, offset, matched ? "true" : "false");
    return matched ? 0 : 3;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: graphics-linkage lock-call-offset unlock-call-offset\n");
        return 1;
    }
    char *end1 = NULL, *end2 = NULL;
    size_t lock_offset = strtoul(argv[1], &end1, 0);
    size_t unlock_offset = strtoul(argv[2], &end2, 0);
    if (*end1 || *end2 || !lock_offset || !unlock_offset ||
        lock_offset > 4096 || unlock_offset > 4096 || (lock_offset & 3) || (unlock_offset & 3)) return 1;
    void *surface = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_LAZY | RTLD_LOCAL);
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!surface || !iokit) return 1;
    puts("{\"evidenceType\":\"owned-process-mapped-code-observation\",\"calls\":[");
    // Offsets are selected from this build's retained dyld_info disassembly.
    // If the call instruction changes, fail instead of returning a target guess.
    int first = inspect(surface, iokit, "IOSurfaceClientLock", lock_offset);
    puts(",");
    int second = inspect(surface, iokit, "IOSurfaceClientUnlock", unlock_offset);
    puts("]}");
    dlclose(iokit);
    dlclose(surface);
    return first || second;
}
