#ifndef WEBRTC_AUDIO_PROCESSING_BRIDGE_H
#define WEBRTC_AUDIO_PROCESSING_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BBCWebRTCAudioProcessor BBCWebRTCAudioProcessor;

typedef struct {
    double echo_return_loss_db;
    double echo_return_loss_enhancement_db;
    double residual_echo_likelihood;
    int32_t delay_ms;
} BBCWebRTCAudioMetrics;

BBCWebRTCAudioProcessor *bbc_apm_create(void);
void bbc_apm_destroy(BBCWebRTCAudioProcessor *processor);

/// Processes one 10 ms, mono, 48 kHz frame. Buffers must contain 480 samples.
/// The render signal is the far-end/system audio reference; capture is microphone audio.
int32_t bbc_apm_process(
    BBCWebRTCAudioProcessor *processor,
    const float *render,
    float *capture,
    int32_t stream_delay_ms
);

BBCWebRTCAudioMetrics bbc_apm_metrics(BBCWebRTCAudioProcessor *processor);

#ifdef __cplusplus
}
#endif

#endif
