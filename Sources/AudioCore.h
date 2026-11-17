#pragma once
#include <stdint.h>
#include <stdbool.h>
typedef struct KTEngine KTEngine;
enum { KT_PROFILE_COUNT = 10, KT_SAMPLES_PER_PROFILE = 11, KT_SAMPLE_COUNT = 110 };
KTEngine *kt_create(void);
void kt_destroy(KTEngine *e);
bool kt_load(KTEngine *e, int index, const float *pcm, uint32_t frames);
int32_t kt_start(KTEngine *e);
void kt_stop(KTEngine *e);
void kt_configure(KTEngine *e, int profile, float volume, bool natural, bool enabled);
void kt_set_key_variation(KTEngine *e, bool enabled);
int kt_key_group(uint16_t keycode);
void kt_trigger(KTEngine *e, bool preview, uint16_t keycode, uint64_t eventTime);
void kt_set_buffer_target(KTEngine *e, uint32_t frames);
void kt_render(KTEngine *e, float *stereo, uint32_t frames, uint64_t outputTime);
uint64_t kt_count(KTEngine *e);
uint64_t kt_input_count(KTEngine *e);
uint64_t kt_dropped(KTEngine *e);
double kt_latency_ms(KTEngine *e);
uint32_t kt_buffer_frames(KTEngine *e);
double kt_device_rate(KTEngine *e);
double kt_device_latency_ms(KTEngine *e);
void kt_refresh_device(KTEngine *e);
