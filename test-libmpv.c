/* Smoke test for libmpv-2.dll: create, initialize with null outputs, load a URL, wait for
 * MPV_EVENT_FILE_LOADED. Usage: test-libmpv.exe <url>. Exit 0 = loaded. Cross-compile:
 *   x86_64-w64-mingw32-gcc test-libmpv.c -Iout/include -Lout -lmpv -o test-libmpv.exe */
#include <stdio.h>
#include <mpv/client.h>

int main(int argc, char **argv)
{
    if (argc < 2)
        return 2;
    unsigned long v = mpv_client_api_version();
    printf("client api %lu.%lu\n", v >> 16, v & 0xffff);
    mpv_handle *h = mpv_create();
    if (!h || mpv_set_option_string(h, "vo", "null") < 0 || mpv_set_option_string(h, "ao", "null") < 0
        || mpv_initialize(h) < 0)
        return 3;
    printf("mpv %s, ffmpeg %s\n", mpv_get_property_string(h, "mpv-version"),
           mpv_get_property_string(h, "ffmpeg-version"));
    mpv_request_log_messages(h, "warn");
    const char *cmd[] = {"loadfile", argv[1], NULL};
    if (mpv_command(h, cmd) < 0)
        return 4;
    for (int i = 0; i < 60; i++) {
        mpv_event *e = mpv_wait_event(h, 1.0);
        if (e->event_id == MPV_EVENT_FILE_LOADED) {
            printf("FILE_LOADED\n");
            return 0;
        }
        if (e->event_id == MPV_EVENT_LOG_MESSAGE) {
            mpv_event_log_message *m = e->data;
            printf("[%s] %s", m->prefix, m->text);
        }
        if (e->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *ef = e->data;
            printf("END_FILE before load: %s\n", mpv_error_string(ef->error));
            return 5;
        }
    }
    return 6;
}
