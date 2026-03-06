//
//  mosh_ios_bridge.h
//  NMMoshShell
//
//  C bridge header for Mosh iOS integration.
//

#ifndef mosh_ios_bridge_h
#define mosh_ios_bridge_h

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Types

/// Mosh state callback function type
typedef void (*mosh_state_callback)(const void *context, const void *buffer, size_t size);

/// Mosh terminal size
typedef struct {
    int16_t rows;
    int16_t cols;
} mosh_terminal_size;

/// Mosh configuration
typedef struct {
    const char *ip;
    const char *port;
    const char *key;
    const char *predict_mode;
    const uint8_t *encoded_state;
    size_t encoded_state_size;
    const char *predict_overwrite;
} mosh_config;

// MARK: - Core Functions

/// Initialize Mosh client
void *mosh_client_create(const mosh_config *config);

/// Start Mosh session
int mosh_client_start(
    void *client,
    FILE *input,
    FILE *output,
    const mosh_terminal_size *size,
    mosh_state_callback callback,
    void *callback_context
);

/// Stop Mosh session
void mosh_client_stop(void *client);

/// Destroy Mosh client
void mosh_client_destroy(void *client);

/// Send user input to Mosh
void mosh_client_send(void *client, const char *input, size_t length);

/// Get current terminal state
int mosh_client_get_state(void *client, void **buffer, size_t *size);

/// Set terminal size
void mosh_client_set_size(void *client, const mosh_terminal_size *size);

/// Check if client is connected
bool mosh_client_is_connected(void *client);

/// Get last error message
const char *mosh_client_get_error(void *client);

// MARK: - Prediction

/// Set prediction mode
void mosh_client_set_prediction_mode(void *client, const char *mode);

/// Get prediction confidence (0.0 to 1.0)
double mosh_client_get_prediction_confidence(void *client);

#ifdef __cplusplus
}
#endif

#endif /* mosh_ios_bridge_h */
