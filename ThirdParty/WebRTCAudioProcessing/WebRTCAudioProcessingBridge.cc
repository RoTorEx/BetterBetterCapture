#include "WebRTCAudioProcessing.h"

#include <limits>

#include <webrtc/modules/audio_processing/include/audio_processing.h>

struct BBCWebRTCAudioProcessor {
    rtc::scoped_refptr<webrtc::AudioProcessing> apm;
    webrtc::StreamConfig stream_config{48000, 1};
};

BBCWebRTCAudioProcessor *bbc_apm_create(void) {
    auto *processor = new BBCWebRTCAudioProcessor;
    processor->apm = webrtc::AudioProcessingBuilder().Create();

    webrtc::AudioProcessing::Config config;
    config.echo_canceller.enabled = true;
    config.echo_canceller.mobile_mode = false;
    config.noise_suppression.enabled = true;
    config.noise_suppression.level =
        webrtc::AudioProcessing::Config::NoiseSuppression::kHigh;
    config.high_pass_filter.enabled = true;
    config.gain_controller2.enabled = true;
    config.gain_controller2.input_volume_controller.enabled = false;
    config.gain_controller2.adaptive_digital.enabled = true;
    config.gain_controller2.adaptive_digital.headroom_db = 8.0f;
    config.gain_controller2.adaptive_digital.max_gain_db = 18.0f;
    config.gain_controller2.adaptive_digital.initial_gain_db = 0.0f;
    config.gain_controller2.adaptive_digital.max_gain_change_db_per_second = 3.0f;
    config.gain_controller2.adaptive_digital.max_output_noise_level_dbfs = -55.0f;
    processor->apm->ApplyConfig(config);
    return processor;
}

void bbc_apm_destroy(BBCWebRTCAudioProcessor *processor) {
    delete processor;
}

int32_t bbc_apm_process(
    BBCWebRTCAudioProcessor *processor,
    const float *render,
    float *capture,
    int32_t stream_delay_ms
) {
    if (!processor || !render || !capture) {
        return -1;
    }

    float *render_output = const_cast<float *>(render);
    const float *render_input[] = {render};
    float *render_outputs[] = {render_output};
    const float *capture_input[] = {capture};
    float *capture_output[] = {capture};

    const int reverse_result = processor->apm->ProcessReverseStream(
        render_input,
        processor->stream_config,
        processor->stream_config,
        render_outputs
    );
    if (reverse_result != 0) {
        return reverse_result;
    }

    processor->apm->set_stream_delay_ms(stream_delay_ms);
    return processor->apm->ProcessStream(
        capture_input,
        processor->stream_config,
        processor->stream_config,
        capture_output
    );
}

BBCWebRTCAudioMetrics bbc_apm_metrics(BBCWebRTCAudioProcessor *processor) {
    BBCWebRTCAudioMetrics result{
        std::numeric_limits<double>::quiet_NaN(),
        std::numeric_limits<double>::quiet_NaN(),
        std::numeric_limits<double>::quiet_NaN(),
        -1
    };
    if (!processor) {
        return result;
    }

    const auto stats = processor->apm->GetStatistics(true);
    if (stats.echo_return_loss) {
        result.echo_return_loss_db = *stats.echo_return_loss;
    }
    if (stats.echo_return_loss_enhancement) {
        result.echo_return_loss_enhancement_db = *stats.echo_return_loss_enhancement;
    }
    if (stats.residual_echo_likelihood) {
        result.residual_echo_likelihood = *stats.residual_echo_likelihood;
    }
    if (stats.delay_ms) {
        result.delay_ms = *stats.delay_ms;
    }
    return result;
}
