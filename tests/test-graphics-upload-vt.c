/* Link vt.c with --wrap=kg_{new,begin,put,put_bytes,end,abort}. */
#undef NDEBUG
#include <assert.h>
#include <string.h>
#include "../vt.h"
#include "../kitty-graphics.h"

static uint8_t packet[16384];
static size_t packet_len, bulk_calls, begins, ends, aborts;

struct kg_engine *__wrap_kg_new(struct terminal *term)
{
    return (struct kg_engine *)packet;
}
void __wrap_kg_begin(struct kg_engine *engine) { packet_len = 0; begins++; }
void __wrap_kg_end(struct kg_engine *engine) { ends++; }
void __wrap_kg_abort(struct kg_engine *engine) { packet_len = 0; aborts++; }
void __wrap_kg_put(struct kg_engine *engine, uint8_t byte) { assert(false); }
void __wrap_kg_put_bytes(struct kg_engine *engine, const uint8_t *data, size_t size)
{
    assert(size > 0 && size <= sizeof(packet) - packet_len);
    memcpy(packet + packet_len, data, size);
    packet_len += size;
    bulk_calls++;
}

static struct terminal *reset(void)
{
    static struct terminal term;
    memset(&term, 0, sizeof(term));
    packet_len = bulk_calls = begins = ends = aborts = 0;
    return &term;
}

int main(void)
{
    static const uint8_t input[] = "\x1b_Gf=32,s=1,v=1;AQIDBA==\x1b\\";
    for (size_t split = 0; split < sizeof(input); split++) {
        struct terminal *term = reset();
        vt_from_slave(term, input, split);
        vt_from_slave(term, input + split, sizeof(input) - 1 - split);
        assert(begins == 1 && ends == 1 && aborts == 0);
        assert(packet_len == sizeof(input) - 6);
        assert(memcmp(packet, input + 3, packet_len) == 0);
        assert(bulk_calls >= 1 && bulk_calls <= 2);
        assert(term->vt.state == 0);
    }
    /* All bytes except the existing ESC/CAN/SUB/C1 controls stay payload. */
    for (unsigned byte = 0; byte <= 255; byte++) {
        struct terminal *term = reset();
        vt_from_slave(term, (const uint8_t *)"\x1b_G", 3);
        const int graphics_state = term->vt.state;
        const uint8_t value = byte;
        vt_from_slave(term, &value, 1);
        if (byte == 0x1b) {
            assert(term->vt.state != graphics_state && aborts == 0);
            vt_from_slave(term, (const uint8_t *)"\\", 1);
            assert(ends == 1 && aborts == 0);
        } else if (byte == 0x18 || byte == 0x1a || (byte >= 0x80 && byte <= 0x9f)) {
            assert(term->vt.state == 0 && aborts == 1 && bulk_calls == 0);
        } else {
            assert(term->vt.state == graphics_state && aborts == 0);
            assert(packet_len == 1 && packet[0] == byte && bulk_calls == 1);
        }
    }
    for (unsigned byte = 0x18; byte <= 0x9f; byte++) {
        if (byte != 0x18 && byte != 0x1a && byte < 0x80)
            continue;
        struct terminal *term = reset();
        uint8_t cancel[] = "\x1b_Gbad?\x1b_Ggood\x1b\\";
        cancel[6] = byte;
        vt_from_slave(term, cancel, sizeof(cancel) - 1);
        assert(aborts == 1 && begins == 2 && ends == 1 && bulk_calls == 2);
        assert(packet_len == 4 && memcmp(packet, "good", 4) == 0);
    }
    struct terminal *term = reset();
    vt_from_slave(term, NULL, 0);
    assert(begins == 0 && bulk_calls == 0);
    vt_from_slave(term, (const uint8_t *)"\x1b_Gabc\x1b[", 8);
    assert(aborts == 1 && ends == 0 && packet_len == 0);
    /* Invalid ESC termination is reprocessed as the start of a new APC. */
    term = reset();
    static const uint8_t restart[] = "\x1b_Gbad\x1b_Ggood\x1b\\";
    vt_from_slave(term, restart, sizeof(restart) - 1);
    assert(aborts == 1 && begins == 2 && ends == 1);
    assert(packet_len == 4 && memcmp(packet, "good", 4) == 0);
    term = reset();
    vt_from_slave(term, (const uint8_t *)"\x1b_G", 3);
    uint8_t large[8192];
    memset(large, 'A', sizeof(large));
    vt_from_slave(term, large, sizeof(large));
    assert(bulk_calls == 1 && packet_len == sizeof(large));
    assert(memcmp(packet, large, sizeof(large)) == 0);
    return 0;
}
