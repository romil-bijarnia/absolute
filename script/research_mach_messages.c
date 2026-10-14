#include <mach/mach.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Each scenario owns every named port it uses. All IPC waits are nonblocking. */
enum { PAYLOAD_BYTES = 16, STORAGE_BYTES = 256, MAX_ROLES = 4 };
typedef union {
    mach_msg_header_t header;
    unsigned char bytes[STORAGE_BYTES];
} frame_t;
typedef struct { mach_port_t name; const char *role; unsigned token; } role_t;
static role_t roles[MAX_ROLES];
static unsigned role_count, sequence, scenario_checks, scenario_failures;
static unsigned total_checks, total_failures, scenario_count;
static bool first_event;

static const char *role_name(mach_port_t name) {
    if (name == MACH_PORT_NULL) return "null";
    if (name == MACH_PORT_DEAD) return "dead-sentinel";
    for (unsigned i = 0; i < role_count; i++) if (roles[i].name == name) return roles[i].role;
    return "unrecognized-name";
}

static mach_port_t role_token(mach_port_t name) {
    if (name == MACH_PORT_NULL || name == MACH_PORT_DEAD) return name;
    for (unsigned i = 0; i < role_count; i++) if (roles[i].name == name) return roles[i].token;
    return UINT32_C(0xfffffffe);
}

static void event(const char *operation) {
    printf("%s{\"sequence\":%u,\"operation\":\"%s\"", first_event ? "" : ",", sequence++, operation);
    first_event = false;
}

static void check(const char *name, bool passed) {
    event("check");
    printf(",\"name\":\"%s\",\"passed\":%s}", name, passed ? "true" : "false");
    scenario_checks++; total_checks++;
    if (!passed) { scenario_failures++; total_failures++; }
}

static void hex_bytes(const unsigned char *bytes, size_t count) {
    putchar('"');
    for (size_t i = 0; i < count; i++) printf("%02x", bytes[i]);
    putchar('"');
}

static void message_json(const frame_t *message, mach_msg_size_t observed_bytes) {
    const mach_msg_header_t *h = &message->header;
    frame_t normalized = *message;
    normalized.header.msgh_remote_port = role_token(h->msgh_remote_port);
    normalized.header.msgh_local_port = role_token(h->msgh_local_port);
    normalized.header.msgh_voucher_port = role_token(h->msgh_voucher_port);
    printf("{\"bits\":%u,\"size\":%u,\"remote_disposition\":%u,\"local_disposition\":%u,"
           "\"remote_role\":\"%s\",\"local_role\":\"%s\",\"voucher_role\":\"%s\",\"id\":%d,"
           "\"normalized_bytes\":", h->msgh_bits, h->msgh_size,
           MACH_MSGH_BITS_REMOTE(h->msgh_bits), MACH_MSGH_BITS_LOCAL(h->msgh_bits),
           role_name(h->msgh_remote_port), role_name(h->msgh_local_port),
           role_name(h->msgh_voucher_port), h->msgh_id);
    hex_bytes(normalized.bytes, observed_bytes <= STORAGE_BYTES ? observed_bytes : STORAGE_BYTES);
    printf("}");
}

static mach_port_urefs_t send_refs(mach_port_t port, kern_return_t *result) {
    mach_port_urefs_t count = 0;
    *result = mach_port_get_refs(mach_task_self(), port, MACH_PORT_RIGHT_SEND, &count);
    return count;
}

static unsigned queue_count(mach_port_t port) {
    mach_port_status_t status = {0};
    mach_msg_type_number_t count = MACH_PORT_RECEIVE_STATUS_COUNT;
    kern_return_t result = mach_port_get_attributes(mach_task_self(), port,
        MACH_PORT_RECEIVE_STATUS, (mach_port_info_t)&status, &count);
    return result == KERN_SUCCESS ? status.mps_msgcount : UINT32_MAX;
}

static void port_json(mach_port_t port) {
    mach_port_type_t type = 0;
    kern_return_t typed = mach_port_type(mach_task_self(), port, &type);
    mach_port_urefs_t send = 0, receive = 0, dead = 0;
    kern_return_t sent = mach_port_get_refs(mach_task_self(), port, MACH_PORT_RIGHT_SEND, &send);
    kern_return_t received = mach_port_get_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, &receive);
    kern_return_t died = mach_port_get_refs(mach_task_self(), port, MACH_PORT_RIGHT_DEAD_NAME, &dead);
    mach_port_status_t status = {0};
    mach_msg_type_number_t count = MACH_PORT_RECEIVE_STATUS_COUNT;
    kern_return_t queued = mach_port_get_attributes(mach_task_self(), port,
        MACH_PORT_RECEIVE_STATUS, (mach_port_info_t)&status, &count);
    printf("{\"role\":\"%s\",\"type_status\":%d,\"type\":%u,"
           "\"send_refs_status\":%d,\"send_refs\":%u,\"receive_refs_status\":%d,\"receive_refs\":%u,"
           "\"dead_refs_status\":%d,\"dead_refs\":%u,\"queue_status\":%d,\"queue_count\":%u,\"queue_limit\":%u}",
           role_name(port), typed, type, sent, send, received, receive, died, dead,
           queued, status.mps_msgcount, status.mps_qlimit);
}

static void snapshot(const char *label, mach_port_t port) {
    event("port_state"); printf(",\"label\":\"%s\",\"state\":", label); port_json(port); printf("}");
}

static void begin_scenario(const char *name) {
    printf("%s{\"name\":\"%s\",\"operations\":[", scenario_count++ ? "," : "", name);
    role_count = sequence = scenario_checks = scenario_failures = 0; first_event = true;
}

static void end_scenario(void) {
    for (unsigned i = 0; i < role_count; i++) {
        mach_port_type_t type = 0;
        mach_port_t port = roles[i].name;
        if (mach_port_type(mach_task_self(), port, &type) == KERN_SUCCESS && (type & MACH_PORT_TYPE_RECEIVE)) {
            kern_return_t result = mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
            event("cleanup_receive_right"); printf(",\"role\":\"%s\",\"status\":%d}", roles[i].role, result);
            check("cleanup_owned_receive_right", result == KERN_SUCCESS);
        }
        if (mach_port_type(mach_task_self(), port, &type) == KERN_SUCCESS) {
            mach_port_right_t right = (type & MACH_PORT_TYPE_DEAD_NAME) ? MACH_PORT_RIGHT_DEAD_NAME : MACH_PORT_RIGHT_SEND;
            mach_port_urefs_t refs = 0;
            kern_return_t inspected = mach_port_get_refs(mach_task_self(), port, right, &refs);
            check("cleanup_reference_count_bounded", inspected == KERN_SUCCESS && refs <= 16);
            for (mach_port_urefs_t ref = 0; inspected == KERN_SUCCESS && ref < refs && ref < 16; ref++) {
                kern_return_t result = mach_port_deallocate(mach_task_self(), port);
                event("cleanup_name_reference"); printf(",\"role\":\"%s\",\"status\":%d}", roles[i].role, result);
                check("cleanup_owned_name_reference", result == KERN_SUCCESS);
            }
        }
    }
    printf("],\"check_count\":%u,\"passed\":%s}", scenario_checks, scenario_failures ? "false" : "true");
}

static mach_port_t create_port(const char *role, bool with_send) {
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t allocated = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    if (allocated == KERN_SUCCESS && role_count < MAX_ROLES) {
        roles[role_count] = (role_t){port, role, role_count + 1}; role_count++;
    }
    event("allocate_receive"); printf(",\"role\":\"%s\",\"token\":%u,\"status\":%d}", role, role_count, allocated);
    check("receive_right_allocated", allocated == KERN_SUCCESS);
    if (allocated == KERN_SUCCESS && with_send) {
        kern_return_t inserted = mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
        event("insert_make_send"); printf(",\"role\":\"%s\",\"status\":%d,\"state\":", role, inserted); port_json(port); printf("}");
        check("send_right_inserted", inserted == KERN_SUCCESS);
    }
    return port;
}

static frame_t make_message(mach_port_t destination, mach_msg_type_name_t disposition, int id) {
    frame_t message = {0};
    message.header.msgh_bits = MACH_MSGH_BITS(disposition, 0);
    message.header.msgh_size = (mach_msg_size_t)(sizeof(mach_msg_header_t) + PAYLOAD_BYTES);
    message.header.msgh_remote_port = destination;
    message.header.msgh_id = id;
    for (unsigned i = 0; i < PAYLOAD_BYTES; i++) message.bytes[sizeof(mach_msg_header_t) + i] = (unsigned char)(i ^ (id & 0xff));
    return message;
}

static mach_msg_return_t send_message(frame_t *message, mach_msg_size_t bytes, const char *label) {
    event("send"); printf(",\"label\":\"%s\",\"send_size\":%u,\"timeout_ms\":0,\"before\":", label, bytes);
    message_json(message, bytes < sizeof(mach_msg_header_t) ? sizeof(mach_msg_header_t) : bytes);
    mach_msg_return_t result = mach_msg(&message->header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
        bytes, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
    printf(",\"status\":%d,\"after\":", result);
    message_json(message, bytes < sizeof(mach_msg_header_t) ? sizeof(mach_msg_header_t) : bytes); printf("}");
    return result;
}

static mach_msg_return_t receive_message(mach_port_t port, frame_t *message, mach_msg_size_t capacity,
                                        bool large, const char *label) {
    memset(message, 0, sizeof(*message));
    mach_msg_return_t result = mach_msg(&message->header,
        MACH_RCV_MSG | MACH_RCV_TIMEOUT | (large ? MACH_RCV_LARGE : 0), 0,
        capacity, port, 0, MACH_PORT_NULL);
    event("receive"); printf(",\"label\":\"%s\",\"role\":\"%s\",\"capacity\":%u,\"large\":%s,"
        "\"timeout_ms\":0,\"status\":%d,\"message\":", label, role_name(port), capacity, large ? "true" : "false", result);
    mach_msg_size_t observed = result == MACH_MSG_SUCCESS ? message->header.msgh_size : sizeof(mach_msg_header_t);
    message_json(message, observed);
    frame_t normalized = *message;
    normalized.header.msgh_remote_port = role_token(message->header.msgh_remote_port);
    normalized.header.msgh_local_port = role_token(message->header.msgh_local_port);
    normalized.header.msgh_voucher_port = role_token(message->header.msgh_voucher_port);
    printf(",\"normalized_storage_prefix_64_bytes\":"); hex_bytes(normalized.bytes, 64);
    if ((result == MACH_MSG_SUCCESS || result == MACH_RCV_TOO_LARGE)
        && message->header.msgh_size <= STORAGE_BYTES - sizeof(mach_msg_trailer_t)) {
        mach_msg_size_t offset = (message->header.msgh_size + 3u) & ~3u;
        mach_msg_trailer_t trailer = {0}; memcpy(&trailer, message->bytes + offset, sizeof(trailer));
        if (trailer.msgh_trailer_size >= sizeof(trailer) && offset + sizeof(trailer) <= capacity) {
            printf(",\"trailer\":{\"offset\":%u,\"type\":%u,\"size\":%u,\"bytes\":", offset,
                   trailer.msgh_trailer_type, trailer.msgh_trailer_size);
            hex_bytes(message->bytes + offset, sizeof(trailer)); printf("}");
        }
    }
    unsigned remaining = queue_count(port);
    printf(",\"queue_count_after\":");
    if (remaining == UINT32_MAX) printf("null}"); else printf("%u}", remaining);
    return result;
}

static void basic_disposition(const char *name, mach_msg_type_name_t disposition) {
    begin_scenario(name);
    mach_port_t port = create_port("destination", true);
    snapshot("before_send", port);
    frame_t outgoing = make_message(port, disposition, 0x414d0001), incoming;
    mach_msg_return_t sent = send_message(&outgoing, outgoing.header.msgh_size, "inline_message");
    check("send_succeeded", sent == MACH_MSG_SUCCESS);
    snapshot("after_send", port);
    kern_return_t refs_status; mach_port_urefs_t refs = send_refs(port, &refs_status);
    check("send_reference_effect", disposition == MACH_MSG_TYPE_COPY_SEND
        ? refs_status == KERN_SUCCESS && refs == 1 : refs_status == KERN_SUCCESS && refs == 0);
    mach_msg_return_t received = receive_message(port, &incoming, STORAGE_BYTES, false, "inline_message");
    check("receive_succeeded", received == MACH_MSG_SUCCESS);
    check("inline_bytes_preserved", received == MACH_MSG_SUCCESS && incoming.header.msgh_size == sizeof(mach_msg_header_t) + PAYLOAD_BYTES
        && memcmp(incoming.bytes + sizeof(mach_msg_header_t), outgoing.bytes + sizeof(mach_msg_header_t), PAYLOAD_BYTES) == 0);
    check("zero_reply_and_voucher", received == MACH_MSG_SUCCESS && incoming.header.msgh_remote_port == MACH_PORT_NULL
        && incoming.header.msgh_voucher_port == MACH_PORT_NULL && incoming.header.msgh_local_port == port);
    check("received_header_dispositions", received == MACH_MSG_SUCCESS && incoming.header.msgh_bits == MACH_MSGH_BITS(0, MACH_MSG_TYPE_PORT_SEND));
    snapshot("after_receive", port);
    end_scenario();
}

static void fifo_and_timeout(void) {
    begin_scenario("queue_limit_fifo_and_move_timeout");
    mach_port_t port = create_port("destination", true);
    mach_port_limits_t limits = {.mpl_qlimit = 2};
    kern_return_t limited = mach_port_set_attributes(mach_task_self(), port, MACH_PORT_LIMITS_INFO,
        (mach_port_info_t)&limits, MACH_PORT_LIMITS_INFO_COUNT);
    event("set_queue_limit"); printf(",\"role\":\"destination\",\"limit\":2,\"status\":%d}", limited);
    check("queue_limit_set", limited == KERN_SUCCESS);
    for (int id = 1; id <= 2; id++) {
        frame_t message = make_message(port, MACH_MSG_TYPE_COPY_SEND, id);
        check("queued_message_sent", send_message(&message, message.header.msgh_size, "queue_fill") == MACH_MSG_SUCCESS);
    }
    snapshot("full_queue_before_move", port);
    frame_t move = make_message(port, MACH_MSG_TYPE_MOVE_SEND, 3);
    mach_msg_return_t overflow = send_message(&move, move.header.msgh_size, "move_on_full_queue");
    check("full_queue_times_out", overflow == MACH_SEND_TIMED_OUT);
    snapshot("after_move_timeout", port);
    kern_return_t refs_status; mach_port_urefs_t refs = send_refs(port, &refs_status);
    check("move_timeout_restores_send_reference", refs_status == KERN_SUCCESS && refs == 1);
    check("failed_send_did_not_queue", queue_count(port) == 2);
    frame_t copy = make_message(port, MACH_MSG_TYPE_COPY_SEND, 4);
    check("copy_on_full_queue_times_out", send_message(&copy, copy.header.msgh_size, "copy_on_full_queue") == MACH_SEND_TIMED_OUT);
    snapshot("after_copy_timeout", port);
    refs = send_refs(port, &refs_status);
    check("copy_timeout_returns_additional_send_reference", refs_status == KERN_SUCCESS && refs == 2);
    check("copy_timeout_rewrites_remote_disposition", MACH_MSGH_BITS_REMOTE(copy.header.msgh_bits) == MACH_MSG_TYPE_MOVE_SEND);
    frame_t received;
    for (int id = 1; id <= 2; id++) {
        mach_msg_return_t result = receive_message(port, &received, STORAGE_BYTES, false, "fifo_drain");
        check("fifo_message_id", result == MACH_MSG_SUCCESS && received.header.msgh_id == id);
    }
    check("returned_move_header_can_retry", send_message(&copy, copy.header.msgh_size, "retry_returned_copy_right") == MACH_MSG_SUCCESS);
    snapshot("after_returned_right_retry", port);
    refs = send_refs(port, &refs_status);
    check("retry_consumes_only_returned_reference", refs_status == KERN_SUCCESS && refs == 1);
    check("retried_payload_received", receive_message(port, &received, STORAGE_BYTES, false, "receive_retried_message") == MACH_MSG_SUCCESS
        && received.header.msgh_id == 4
        && memcmp(received.bytes + sizeof(mach_msg_header_t), copy.bytes + sizeof(mach_msg_header_t), PAYLOAD_BYTES) == 0);
    check("empty_receive_times_out", receive_message(port, &received, STORAGE_BYTES, false, "empty_queue") == MACH_RCV_TIMED_OUT);
    end_scenario();
}

static void receive_capacity(mach_msg_size_t capacity, bool large) {
    char name[80]; snprintf(name, sizeof(name), "receive_capacity_%u_large_%s", capacity, large ? "true" : "false");
    begin_scenario(name);
    mach_port_t port = create_port("destination", true);
    frame_t outgoing = make_message(port, MACH_MSG_TYPE_COPY_SEND, 0x414d0010), received;
    check("initial_send_succeeded", send_message(&outgoing, outgoing.header.msgh_size, "before_bounded_receive") == MACH_MSG_SUCCESS);
    snapshot("before_bounded_receive", port);
    mach_msg_return_t first = receive_message(port, &received, capacity, large, "bounded_receive");
    check("capacity_includes_default_trailer", first == (capacity < sizeof(mach_msg_header_t) + PAYLOAD_BYTES + sizeof(mach_msg_trailer_t)
        ? MACH_RCV_TOO_LARGE : MACH_MSG_SUCCESS));
    if (first == MACH_RCV_TOO_LARGE) {
        check("too_large_reported_size", received.header.msgh_size == (large ? sizeof(mach_msg_header_t) + PAYLOAD_BYTES : sizeof(mach_msg_header_t)));
        mach_msg_trailer_t error_trailer = {0}; memcpy(&error_trailer, received.bytes + sizeof(mach_msg_header_t), sizeof(error_trailer));
        check("too_large_minimal_trailer_capacity", error_trailer.msgh_trailer_size == (!large && capacity >= sizeof(mach_msg_header_t) + sizeof(mach_msg_trailer_t)
            ? sizeof(mach_msg_trailer_t) : 0));
        check("too_large_queue_effect", queue_count(port) == (large ? 1u : 0u));
        mach_msg_return_t next = receive_message(port, &received, STORAGE_BYTES, false, "retry_with_room");
        check("large_option_preserves_message", large ? next == MACH_MSG_SUCCESS && received.header.msgh_id == outgoing.header.msgh_id
                                                      : next == MACH_RCV_TIMED_OUT);
    } else {
        check("successful_receive_consumes_message", queue_count(port) == 0);
    }
    end_scenario();
}

static void receive_only_send(void) {
    begin_scenario("copy_send_on_receive_only_name");
    mach_port_t port = create_port("destination", false);
    frame_t message = make_message(port, MACH_MSG_TYPE_COPY_SEND, 1);
    snapshot("before_invalid_send", port);
    mach_msg_return_t result = send_message(&message, message.header.msgh_size, "receive_only_destination");
    check("send_without_send_right_fails", result == MACH_SEND_INVALID_DEST);
    snapshot("after_invalid_send", port);
    check("invalid_send_did_not_queue", queue_count(port) == 0);
    end_scenario();
}

static void destroy_receive(void) {
    begin_scenario("receive_destruction_and_dead_send_name");
    mach_port_t port = create_port("destination", true);
    frame_t message = make_message(port, MACH_MSG_TYPE_COPY_SEND, 1), incoming;
    check("queued_before_destruction", send_message(&message, message.header.msgh_size, "queued_message") == MACH_MSG_SUCCESS);
    kern_return_t destroyed = mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
    event("destroy_receive_right"); printf(",\"role\":\"destination\",\"status\":%d}", destroyed);
    check("receive_right_destroyed", destroyed == KERN_SUCCESS);
    snapshot("after_receive_destruction", port);
    mach_port_type_t type = 0;
    check("send_name_became_dead", mach_port_type(mach_task_self(), port, &type) == KERN_SUCCESS && (type & MACH_PORT_TYPE_DEAD_NAME));
    message = make_message(port, MACH_MSG_TYPE_COPY_SEND, 2);
    check("send_to_dead_name_fails", send_message(&message, message.header.msgh_size, "dead_destination") == MACH_SEND_INVALID_DEST);
    check("receive_from_dead_name_fails", receive_message(port, &incoming, STORAGE_BYTES, false, "dead_receive") == MACH_RCV_INVALID_NAME);
    kern_return_t released = mach_port_deallocate(mach_task_self(), port);
    event("release_dead_name"); printf(",\"role\":\"destination\",\"status\":%d}", released);
    check("dead_name_released", released == KERN_SUCCESS);
    snapshot("after_dead_name_release", port);
    end_scenario();
}

static void bounded_invalid_sizes(void) {
    begin_scenario("bounded_size_validation");
    mach_port_t port = create_port("destination", true);
    frame_t message = make_message(port, MACH_MSG_TYPE_COPY_SEND, 1), incoming;
    mach_msg_return_t small = send_message(&message, (mach_msg_size_t)sizeof(mach_msg_header_t) - 4, "smaller_than_header");
    check("undersized_header_rejected", small == MACH_SEND_MSG_TOO_SMALL);
    check("undersized_send_did_not_queue", queue_count(port) == 0);
    message = make_message(port, MACH_MSG_TYPE_COPY_SEND, 2);
    message.header.msgh_size = sizeof(mach_msg_header_t);
    mach_msg_return_t mismatch = send_message(&message, (mach_msg_size_t)sizeof(mach_msg_header_t) + PAYLOAD_BYTES, "header_size_differs_from_send_argument");
    check("size_argument_message_sent", mismatch == MACH_MSG_SUCCESS);
    mach_msg_return_t received = receive_message(port, &incoming, STORAGE_BYTES, false, "argument_sized_message");
    check("send_argument_determines_received_size", received == MACH_MSG_SUCCESS && incoming.header.msgh_size == sizeof(mach_msg_header_t) + PAYLOAD_BYTES);
    end_scenario();
}

static void send_size_alignment(mach_msg_size_t size) {
    char name[64]; snprintf(name, sizeof(name), "send_size_%u", size);
    begin_scenario(name);
    mach_port_t port = create_port("destination", true);
    frame_t outgoing = make_message(port, MACH_MSG_TYPE_COPY_SEND, (int)size), incoming;
    outgoing.header.msgh_size = size;
    mach_msg_return_t result = send_message(&outgoing, size, "declared_send_size");
    check("send_size_alignment_outcome", result == (size % 4 == 0 ? MACH_MSG_SUCCESS : MACH_SEND_MSG_TOO_SMALL));
    if (result == MACH_MSG_SUCCESS) {
        mach_msg_return_t received = receive_message(port, &incoming, STORAGE_BYTES, false, "declared_size_receive");
        check("admitted_size_preserved", received == MACH_MSG_SUCCESS && incoming.header.msgh_size == size);
    } else {
        check("rejected_size_did_not_queue", queue_count(port) == 0);
    }
    end_scenario();
}

static void invalid_disposition(mach_msg_type_name_t disposition) {
    char name[64]; snprintf(name, sizeof(name), "remote_disposition_%u", disposition);
    begin_scenario(name);
    mach_port_t port = create_port("destination", true);
    frame_t message = make_message(port, disposition, 1);
    mach_msg_return_t result = send_message(&message, message.header.msgh_size, "unsupported_remote_disposition");
    check("unsupported_remote_disposition_rejected", result == MACH_SEND_INVALID_HEADER);
    snapshot("after_invalid_disposition", port);
    end_scenario();
}

static void queue_full_size_mismatch(void) {
    begin_scenario("queue_full_header_size_differs_from_send_argument");
    mach_port_t port = create_port("destination", true);
    mach_port_limits_t limits = {.mpl_qlimit = 1};
    kern_return_t limited = mach_port_set_attributes(mach_task_self(), port, MACH_PORT_LIMITS_INFO,
        (mach_port_info_t)&limits, MACH_PORT_LIMITS_INFO_COUNT);
    event("set_queue_limit"); printf(",\"role\":\"destination\",\"limit\":1,\"status\":%d}", limited);
    check("queue_limit_set", limited == KERN_SUCCESS);
    frame_t fill = make_message(port, MACH_MSG_TYPE_COPY_SEND, 1), incoming;
    check("queue_filled", send_message(&fill, fill.header.msgh_size, "fill_queue") == MACH_MSG_SUCCESS);
    frame_t copy = make_message(port, MACH_MSG_TYPE_COPY_SEND, 2);
    copy.header.msgh_size = sizeof(mach_msg_header_t);
    check("mismatched_copy_times_out", send_message(&copy, sizeof(mach_msg_header_t) + PAYLOAD_BYTES, "mismatched_copy_timeout") == MACH_SEND_TIMED_OUT);
    snapshot("after_mismatched_copy_timeout", port);
    check("copy_error_reports_send_argument_size", copy.header.msgh_size == sizeof(mach_msg_header_t) + PAYLOAD_BYTES);
    frame_t move = make_message(port, MACH_MSG_TYPE_MOVE_SEND, 3);
    move.header.msgh_size = sizeof(mach_msg_header_t);
    check("mismatched_move_times_out", send_message(&move, sizeof(mach_msg_header_t) + PAYLOAD_BYTES, "mismatched_move_timeout") == MACH_SEND_TIMED_OUT);
    snapshot("after_mismatched_move_timeout", port);
    check("move_error_reports_send_argument_size", move.header.msgh_size == sizeof(mach_msg_header_t) + PAYLOAD_BYTES);
    check("failed_sends_preserve_queue", queue_count(port) == 1);
    check("queued_original_drained", receive_message(port, &incoming, STORAGE_BYTES, false, "drain_original") == MACH_MSG_SUCCESS && incoming.header.msgh_id == 1);
    end_scenario();
}

int main(int argc, char **argv) {
    if (argc > 2 || (argc == 2 && strcmp(argv[1], "--json") != 0)) {
        fprintf(stderr, "Usage: research_mach_messages [--json]\n"); return 2;
    }
    printf("{\"schema\":1,\"abi\":{\"header_bytes\":%zu,\"port_name_bytes\":%zu,\"payload_bytes\":%u,"
           "\"physical_buffer_bytes\":%u,\"default_trailer_header_bytes\":%zu,\"port_offsets\":[%zu,%zu,%zu]},\"constants\":{",
           sizeof(mach_msg_header_t), sizeof(mach_port_t), PAYLOAD_BYTES, STORAGE_BYTES, sizeof(mach_msg_trailer_t),
           offsetof(mach_msg_header_t, msgh_remote_port), offsetof(mach_msg_header_t, msgh_local_port), offsetof(mach_msg_header_t, msgh_voucher_port));
#define CONSTANT(name) printf("\"" #name "\":%llu,", (unsigned long long)(name))
    CONSTANT(KERN_SUCCESS); CONSTANT(KERN_INVALID_NAME); CONSTANT(KERN_INVALID_RIGHT);
    CONSTANT(MACH_MSG_SUCCESS); CONSTANT(MACH_SEND_MSG); CONSTANT(MACH_RCV_MSG); CONSTANT(MACH_SEND_TIMEOUT);
    CONSTANT(MACH_RCV_TIMEOUT); CONSTANT(MACH_RCV_LARGE); CONSTANT(MACH_SEND_TIMED_OUT); CONSTANT(MACH_RCV_TIMED_OUT);
    CONSTANT(MACH_RCV_TOO_LARGE); CONSTANT(MACH_SEND_INVALID_DEST); CONSTANT(MACH_SEND_INVALID_RIGHT);
    CONSTANT(MACH_SEND_INVALID_HEADER); CONSTANT(MACH_SEND_MSG_TOO_SMALL); CONSTANT(MACH_RCV_INVALID_NAME);
    CONSTANT(MACH_MSG_TYPE_COPY_SEND); CONSTANT(MACH_MSG_TYPE_MOVE_SEND); CONSTANT(MACH_MSG_TYPE_MAKE_SEND);
    CONSTANT(MACH_MSG_TYPE_PORT_SEND); CONSTANT(MACH_PORT_TYPE_SEND); CONSTANT(MACH_PORT_TYPE_RECEIVE);
    CONSTANT(MACH_PORT_TYPE_DEAD_NAME); CONSTANT(MACH_PORT_QLIMIT_DEFAULT);
#undef CONSTANT
    printf("\"MACH_MSG_TRAILER_FORMAT_0\":%u},\"normalization\":\"Port-name words use scenario-local role tokens; all other header and payload bytes are preserved. Token 0 is null and token 4294967295 is the dead-name sentinel.\",\"scenarios\":[", MACH_MSG_TRAILER_FORMAT_0);
    basic_disposition("copy_send_inline", MACH_MSG_TYPE_COPY_SEND);
    basic_disposition("move_send_inline", MACH_MSG_TYPE_MOVE_SEND);
    fifo_and_timeout();
    queue_full_size_mismatch();
    for (mach_msg_size_t capacity = 24; capacity <= 48; capacity += 8) {
        receive_capacity(capacity, false); receive_capacity(capacity, true);
    }
    receive_only_send(); destroy_receive(); bounded_invalid_sizes();
    const mach_msg_size_t sizes[] = {24, 25, 27, 28, 39, 40};
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) send_size_alignment(sizes[i]);
    invalid_disposition(0); invalid_disposition(MACH_MSG_TYPE_MOVE_RECEIVE);
    printf("],\"scenario_count\":%u,\"check_count\":%u,\"passed\":%s}\n", scenario_count, total_checks, total_failures ? "false" : "true");
    return total_failures ? 1 : 0;
}
