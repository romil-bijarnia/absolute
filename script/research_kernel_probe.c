#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/mach_vm.h>
#include <mach/semaphore.h>
#include <mach/sync_policy.h>
#include <sys/event.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

/* All ports, memory, semaphores and descriptors belong to this process. */
static unsigned total_checks = 0;
static unsigned failed_checks = 0;

static void record(const char *name, bool passed) {
    printf("%s\n    \"%s\": %s", total_checks ? "," : "", name, passed ? "true" : "false");
    total_checks++;
    if (!passed) failed_checks++;
}

int main(void) {
    printf("{\n  \"checks\": {");
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t port_alloc = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    record("allocate_receive_right", port_alloc == KERN_SUCCESS);
    kern_return_t insert = port_alloc == KERN_SUCCESS
        ? mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND)
        : KERN_FAILURE;
    record("insert_send_right", insert == KERN_SUCCESS);
    mach_port_urefs_t send_refs = 0;
    kern_return_t refs_result = insert == KERN_SUCCESS
        ? mach_port_get_refs(mach_task_self(), port, MACH_PORT_RIGHT_SEND, &send_refs)
        : KERN_FAILURE;
    record("send_right_has_one_user_reference", refs_result == KERN_SUCCESS && send_refs == 1);

    struct payload_message {
        mach_msg_header_t header;
        uint64_t payload;
    };
    struct payload_message outgoing = {0};
    outgoing.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    outgoing.header.msgh_size = sizeof(outgoing);
    outgoing.header.msgh_remote_port = port;
    outgoing.header.msgh_id = 0x41425331;
    outgoing.payload = UINT64_C(0x1020304050607080);
    mach_msg_return_t sent = insert == KERN_SUCCESS
        ? mach_msg(&outgoing.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof(outgoing),
                   0, MACH_PORT_NULL, 1000, MACH_PORT_NULL)
        : MACH_SEND_INVALID_DEST;
    record("send_message_to_owned_port", sent == MACH_MSG_SUCCESS);
    struct {
        struct payload_message message;
        uint8_t trailer[MAX_TRAILER_SIZE];
    } incoming = {0};
    mach_msg_return_t received = sent == MACH_MSG_SUCCESS
        ? mach_msg(&incoming.message.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0,
                   sizeof(incoming), port, 1000, MACH_PORT_NULL)
        : MACH_RCV_INVALID_NAME;
    record("receive_message_from_owned_port", received == MACH_MSG_SUCCESS);
    record("message_id_size_and_payload_preserved",
           received == MACH_MSG_SUCCESS
           && incoming.message.header.msgh_id == outgoing.header.msgh_id
           && incoming.message.header.msgh_size == sizeof(outgoing)
           && incoming.message.payload == outgoing.payload);
    record("received_header_names_receive_port",
           received == MACH_MSG_SUCCESS && incoming.message.header.msgh_local_port == port);
    mach_msg_return_t empty_receive = received == MACH_MSG_SUCCESS
        ? mach_msg(&incoming.message.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0,
                   sizeof(incoming), port, 0, MACH_PORT_NULL)
        : MACH_RCV_INVALID_NAME;
    record("empty_port_receive_times_out", empty_receive == MACH_RCV_TIMED_OUT);
    outgoing.header.msgh_remote_port = MACH_PORT_NULL;
    mach_msg_return_t invalid_send = mach_msg(&outgoing.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                                              sizeof(outgoing), 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
    record("null_destination_send_fails", invalid_send == MACH_SEND_INVALID_DEST);
    kern_return_t release_send = insert == KERN_SUCCESS
        ? mach_port_deallocate(mach_task_self(), port) : KERN_SUCCESS;
    kern_return_t release_receive = port_alloc == KERN_SUCCESS
        ? mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1) : KERN_FAILURE;
    record("destroy_owned_port", release_send == KERN_SUCCESS && release_receive == KERN_SUCCESS);

    mach_vm_address_t address = 0;
    mach_vm_size_t size = vm_page_size;
    kern_return_t allocated = mach_vm_allocate(mach_task_self(), &address, size, VM_FLAGS_ANYWHERE);
    record("allocate_owned_virtual_memory", allocated == KERN_SUCCESS);
    bool zero_filled = allocated == KERN_SUCCESS;
    if (allocated == KERN_SUCCESS) {
        const uint8_t *bytes = (const uint8_t *)(uintptr_t)address;
        for (mach_vm_size_t i = 0; i < size; i++) if (bytes[i] != 0) zero_filled = false;
        *(uint64_t *)(uintptr_t)address = UINT64_C(0x5354415445444154);
    }
    record("anonymous_page_starts_zero_filled", zero_filled);
    kern_return_t protected_read = allocated == KERN_SUCCESS
        ? mach_vm_protect(mach_task_self(), address, size, false, VM_PROT_READ) : KERN_FAILURE;
    record("protect_owned_page_read_only", protected_read == KERN_SUCCESS);
    mach_vm_address_t region_address = address;
    mach_vm_size_t region_size = 0;
    vm_region_basic_info_data_64_t info = {0};
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    kern_return_t region_result = allocated == KERN_SUCCESS
        ? mach_vm_region(mach_task_self(), &region_address, &region_size, VM_REGION_BASIC_INFO_64,
                         (vm_region_info_t)&info, &info_count, &object_name)
        : KERN_FAILURE;
    record("region_reports_read_without_write",
           region_result == KERN_SUCCESS && region_address <= address
           && region_address + region_size >= address + size
           && (info.protection & VM_PROT_READ) && !(info.protection & VM_PROT_WRITE));
    if (object_name != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object_name);
    kern_return_t restored_write = allocated == KERN_SUCCESS
        ? mach_vm_protect(mach_task_self(), address, size, false, VM_PROT_READ | VM_PROT_WRITE)
        : KERN_FAILURE;
    if (restored_write == KERN_SUCCESS) *(uint64_t *)(uintptr_t)address = UINT64_C(0x4452415741424C45);
    record("restore_write_permission_and_read_back",
           restored_write == KERN_SUCCESS
           && *(uint64_t *)(uintptr_t)address == UINT64_C(0x4452415741424C45));
    kern_return_t deallocated = allocated == KERN_SUCCESS
        ? mach_vm_deallocate(mach_task_self(), address, size) : KERN_FAILURE;
    record("deallocate_owned_virtual_memory", deallocated == KERN_SUCCESS);

    semaphore_t semaphore = MACH_PORT_NULL;
    kern_return_t sem_created = semaphore_create(mach_task_self(), &semaphore, SYNC_POLICY_FIFO, 0);
    record("create_owned_semaphore", sem_created == KERN_SUCCESS);
    mach_timespec_t no_wait = {0, 0};
    kern_return_t sem_empty = sem_created == KERN_SUCCESS
        ? semaphore_timedwait(semaphore, no_wait) : KERN_FAILURE;
    record("empty_semaphore_wait_times_out", sem_empty == KERN_OPERATION_TIMED_OUT);
    kern_return_t sem_signal = sem_created == KERN_SUCCESS ? semaphore_signal(semaphore) : KERN_FAILURE;
    kern_return_t sem_wait = sem_signal == KERN_SUCCESS
        ? semaphore_timedwait(semaphore, no_wait) : KERN_FAILURE;
    record("signal_makes_one_semaphore_wait_succeed", sem_wait == KERN_SUCCESS);
    kern_return_t sem_drained = sem_created == KERN_SUCCESS
        ? semaphore_timedwait(semaphore, no_wait) : KERN_FAILURE;
    record("semaphore_signal_is_consumed_once", sem_drained == KERN_OPERATION_TIMED_OUT);
    kern_return_t sem_destroy = sem_created == KERN_SUCCESS
        ? semaphore_destroy(mach_task_self(), semaphore) : KERN_FAILURE;
    record("destroy_owned_semaphore", sem_destroy == KERN_SUCCESS);

    int descriptors[2] = {-1, -1};
    int queue = kqueue();
    bool pipe_created = pipe(descriptors) == 0;
    struct kevent change = {0}, event = {0};
    EV_SET(&change, pipe_created ? (uintptr_t)descriptors[0] : 0, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, NULL);
    bool registered = queue >= 0 && pipe_created && kevent(queue, &change, 1, NULL, 0, NULL) == 0;
    record("register_owned_pipe_with_kqueue", registered);
    uint64_t pipe_value = UINT64_C(0x4B51554555453031), read_value = 0;
    ssize_t written = registered ? write(descriptors[1], &pipe_value, sizeof(pipe_value)) : -1;
    struct timespec short_wait = {0, 500000000};
    int ready = written == sizeof(pipe_value) ? kevent(queue, NULL, 0, &event, 1, &short_wait) : -1;
    record("kqueue_reports_readable_bytes",
           ready == 1 && event.filter == EVFILT_READ
           && event.ident == (uintptr_t)descriptors[0] && event.data == sizeof(pipe_value));
    ssize_t read_count = ready == 1 ? read(descriptors[0], &read_value, sizeof(read_value)) : -1;
    record("pipe_message_round_trip", read_count == sizeof(read_value) && read_value == pipe_value);
    struct timespec poll = {0, 0};
    int after_read = registered ? kevent(queue, NULL, 0, &event, 1, &poll) : -1;
    record("drained_pipe_is_not_reported_readable", after_read == 0);
    if (descriptors[0] >= 0) close(descriptors[0]);
    if (descriptors[1] >= 0) close(descriptors[1]);
    if (queue >= 0) close(queue);

    mach_timebase_info_data_t timebase = {0};
    kern_return_t timebase_result = mach_timebase_info(&timebase);
    uint64_t before = mach_absolute_time();
    struct timespec delay = {0, 2000000};
    nanosleep(&delay, NULL);
    uint64_t after = mach_absolute_time();
    record("mach_clock_advances_with_nonzero_timebase",
           timebase_result == KERN_SUCCESS && timebase.numer && timebase.denom && after > before);
    printf("\n  },\n  \"observations\": {\n");
    printf("    \"vm_page_bytes\": %llu,\n", (unsigned long long)vm_page_size);
    printf("    \"timebase_numer\": %u, \"timebase_denom\": %u,\n", timebase.numer, timebase.denom);
    printf("    \"empty_receive_status\": %d, \"null_send_status\": %d,\n", empty_receive, invalid_send);
    printf("    \"empty_semaphore_status\": %d,\n", sem_empty);
    printf("    \"message_bytes\": %zu\n", sizeof(outgoing));
    printf("  },\n  \"check_count\": %u,\n  \"passed\": %s\n}\n",
           total_checks, failed_checks ? "false" : "true");
    return failed_checks ? 1 : 0;
}
