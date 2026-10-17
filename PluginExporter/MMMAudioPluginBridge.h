/* C declarations for MMMAudioPluginBridge.mojo.
 *
 * Audio buffers are interleaved float: frame i, channel c at buf[i * chans + c].
 * Strings are NUL-terminated UTF-8. Message functions copy their arguments.
 */
#ifndef MMM_AUDIO_PLUGIN_BRIDGE_H
#define MMM_AUDIO_PLUGIN_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef intptr_t mmm_handle; /* 0 means no engine */

#define MMM_OK 0
#define MMM_ERROR -1

/* lifecycle / configuration */
mmm_handle mmm_plugin_new(const char *graph_lib, double sample_rate, intptr_t block_size,
                          intptr_t num_in_chans, intptr_t num_out_chans);
void mmm_plugin_free(mmm_handle h);
/* Process-wide: where graphs look up relative file paths they can't find
 * from the working directory. Call before mmm_plugin_new / set_sample_rate. */
void mmm_plugin_set_resource_dir(const char *path);
int mmm_plugin_set_sample_rate(mmm_handle h, double sample_rate); /* rebuilds the graph */
int mmm_plugin_set_block_size(mmm_handle h, intptr_t block_size);
double mmm_plugin_get_sample_rate(mmm_handle h);
intptr_t mmm_plugin_get_block_size(mmm_handle h);
intptr_t mmm_plugin_get_num_in_chans(mmm_handle h);
intptr_t mmm_plugin_get_num_out_chans(mmm_handle h);

/* audio: in may be NULL (silence). Buffers longer than block_size are
 * rendered as several blocks. */
int mmm_plugin_next(mmm_handle h, const float *in, float *out, intptr_t frames);
int mmm_plugin_next1(mmm_handle h, const float *in_frame, float *out_frame);

/* messages - the same set MMMAudio.py sends */
void mmm_plugin_send_bool(mmm_handle h, const char *key, int value);
void mmm_plugin_send_bools(mmm_handle h, const char *key, const uint8_t *values, intptr_t count);
void mmm_plugin_send_float(mmm_handle h, const char *key, double value);
void mmm_plugin_send_floats(mmm_handle h, const char *key, const double *values, intptr_t count);
void mmm_plugin_send_int(mmm_handle h, const char *key, int64_t value);
void mmm_plugin_send_ints(mmm_handle h, const char *key, const int64_t *values, intptr_t count);
void mmm_plugin_send_trig(mmm_handle h, const char *key);
void mmm_plugin_send_trigs(mmm_handle h, const char *key, const uint8_t *values, intptr_t count);
void mmm_plugin_send_string(mmm_handle h, const char *key, const char *value);
void mmm_plugin_send_strings(mmm_handle h, const char *key, const char *const *values, intptr_t count);
void mmm_plugin_update_mouse_pos(mmm_handle h, double x, double y);
void mmm_plugin_set_screen_dims(mmm_handle h, double width, double height);

#ifdef __cplusplus
}
#endif

#endif
