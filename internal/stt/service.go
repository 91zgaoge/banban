// Package stt provides speech-to-text functionality for the companion app.
// It supports FunASR as the backend ASR service.
package stt

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Service defines the interface for speech-to-text operations.
type Service interface {
	// Transcribe converts audio data to text.
	// format is the audio codec (e.g., "opus", "pcm", "wav").
	Transcribe(ctx context.Context, audio []byte, format string) (string, error)
}

// FunASRClient is a client for the FunASR WebSocket API.
type FunASRClient struct {
	endpoint string
	log      *slog.Logger
}

// FunASROptions configures the FunASR client.
type FunASROptions struct {
	Endpoint string
	Timeout  time.Duration
}

// NewFunASRClient creates a new FunASR WebSocket client.
func NewFunASRClient(log *slog.Logger, opts FunASROptions) *FunASRClient {
	endpoint := opts.Endpoint
	if endpoint == "" {
		endpoint = "ws://memoh-funasr:10095"
	}
	return &FunASRClient{
		endpoint: endpoint,
		log:      log.With(slog.String("component", "funasr")),
	}
}

// FunASR websocket message types
const (
	MsgTypeStart       = "start"
	MsgTypeChange      = "change"
	MsgTypeEnd         = "end"
	MsgTypeSpeechData  = "speech"
	MsgTypePartial     = "partial"
	MsgTypeFinal       = "final"
	MsgTypeFull        = "full"
	MsgTypeError       = "error"
)

// startMessage is sent to initialize the ASR session
type startMessage struct {
	Mode      string `json:"mode"`       // "2pass" for online+offline
	ChunkSize string `json:"chunk_size"` // "5,10,5" for low latency
	WaveFormat string `json:"wav_format,omitempty"`
}

// asrResult represents ASR result from FunASR
type asrResult struct {
	Mode      string `json:"mode"`
	Text      string `json:"text"`
	StampSents []struct {
		TextSeg   string `json:"text_seg"`
		StartTime int    `json:"start"`
		EndTime   int    `json:"end"`
	} `json:"stamp_sents,omitempty"`
	IsFinal bool `json:"is_final,omitempty"`
}

// Transcribe converts audio to text using FunASR WebSocket.
// For simplicity, we send all audio at once and wait for final result.
func (c *FunASRClient) Transcribe(ctx context.Context, audio []byte, format string) (string, error) {
	if len(audio) == 0 {
		return "", fmt.Errorf("stt: empty audio data")
	}

	// Connect to FunASR websocket
	wsURL := c.endpoint
	c.log.Debug("connecting to FunASR", slog.String("url", wsURL))

	ws, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		return "", fmt.Errorf("stt: failed to connect to FunASR: %w", err)
	}
	defer ws.Close()

	// Send start message
	start := startMessage{
		Mode:       "offline", // Use offline mode for complete audio file
		WaveFormat: format,
	}
	if err := ws.WriteJSON(map[string]any{
		"mode":        start.Mode,
		"chunk_size":  "0",
		"wav_format":  format,
	}); err != nil {
		return "", fmt.Errorf("stt: failed to send start message: %w", err)

	}

	// Send audio data as binary
	c.log.Debug("sending audio data", slog.Int("bytes", len(audio)), slog.String("format", format))
	if err := ws.WriteMessage(websocket.BinaryMessage, audio); err != nil {
		return "", fmt.Errorf("stt: failed to send audio data: %w", err)
	}

	// Send end message
	if err := ws.WriteJSON(map[string]string{"type": "end"}); err != nil {
		return "", fmt.Errorf("stt: failed to send end message: %w", err)
	}

	// Wait for final result
	resultChan := make(chan string, 1)
	errChan := make(chan error, 1)
	var wg sync.WaitGroup
	wg.Add(1)

	go func() {
		defer wg.Done()
		var finalText string
		for {
			select {
			case <-ctx.Done():
				errChan <- ctx.Err()
				return
			default:
			}

			ws.SetReadDeadline(time.Now().Add(30 * time.Second))
			msgType, data, err := ws.ReadMessage()
			if err != nil {
				errChan <- fmt.Errorf("stt: websocket read error: %w", err)
				return
			}

			if msgType == websocket.TextMessage {
				c.log.Debug("received message", slog.String("data", string(data)))

				// Try to parse as ASR result
				var result asrResult
				if err := json.Unmarshal(data, &result); err == nil && result.Text != "" {
					finalText = result.Text
					if result.IsFinal {
						resultChan <- finalText
						return
					}
				}

				// Check for error message
				var errMsg map[string]string
				if err := json.Unmarshal(data, &errMsg); err == nil {
					if msg, ok := errMsg["error"]; ok {
						errChan <- fmt.Errorf("stt: FunASR error: %s", msg)
						return
					}
				}
			}
		}
	}()

	select {
	case text := <-resultChan:
		c.log.Debug("ASR result", slog.String("text", text))
		return text, nil
	case err := <-errChan:
		return "", err
	case <-time.After(30 * time.Second):
		return "", fmt.Errorf("stt: timeout waiting for ASR result")
	}
}

// NoOpClient is a no-op STT client that returns an error.
// Used when STT is not configured.
type NoOpClient struct{}

// Transcribe implements the Service interface but always returns an error.
func (n *NoOpClient) Transcribe(ctx context.Context, audio []byte, format string) (string, error) {
	return "", fmt.Errorf("stt: service not configured")
}
