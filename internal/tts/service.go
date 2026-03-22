// Package tts provides text-to-speech functionality for the companion app.
// It supports Kokoro-FastAPI as the backend TTS service.
package tts

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"
)

// Service defines the interface for text-to-speech operations.
type Service interface {
	// Synthesize converts text to speech audio.
	// Returns audio data (typically WAV or MP3 format).
	Synthesize(ctx context.Context, text string, voice string) ([]byte, error)
}

// KokoroClient is a client for the Kokoro-FastAPI HTTP API.
type KokoroClient struct {
	endpoint string
	client   *http.Client
	log      *slog.Logger
}

// KokoroOptions configures the Kokoro client.
type KokoroOptions struct {
	Endpoint string
	Timeout  time.Duration
}

// NewKokoroClient creates a new Kokoro-FastAPI HTTP client.
func NewKokoroClient(log *slog.Logger, opts KokoroOptions) *KokoroClient {
	timeout := opts.Timeout
	if timeout == 0 {
		timeout = 30 * time.Second
	}
	endpoint := opts.Endpoint
	if endpoint == "" {
		endpoint = "http://memoh-kokoro-tts:8880"
	}
	return &KokoroClient{
		endpoint: endpoint,
		client:   &http.Client{Timeout: timeout},
		log:      log.With(slog.String("component", "kokoro-tts")),
	}
}

// speechRequest represents the request body for Kokoro TTS API.
type speechRequest struct {
	Model          string  `json:"model"`
	Input          string  `json:"input"`
	Voice          string  `json:"voice"`
	ResponseFormat string  `json:"response_format"`
	Speed          float64 `json:"speed"`
}

// Synthesize converts text to speech using Kokoro-FastAPI.
func (c *KokoroClient) Synthesize(ctx context.Context, text string, voice string) ([]byte, error) {
	if text == "" {
		return nil, fmt.Errorf("tts: empty text")
	}
	if voice == "" {
		voice = "af_bella" // default voice
	}

	reqBody := speechRequest{
		Model:          "kokoro",
		Input:          text,
		Voice:          voice,
		ResponseFormat: "wav", // Use WAV for compatibility
		Speed:          1.0,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("tts: failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.endpoint+"/v1/audio/speech", bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("tts: failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	c.log.Debug("sending TTS request", slog.String("text", text), slog.String("voice", voice))

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("tts: request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("tts: unexpected status %d: %s", resp.StatusCode, string(body))
	}

	audioData, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("tts: failed to read response: %w", err)
	}

	c.log.Debug("TTS result", slog.Int("audio_bytes", len(audioData)))
	return audioData, nil
}

// NoOpClient is a no-op TTS client that returns an error.
// Used when TTS is not configured.
type NoOpClient struct{}

// Synthesize implements the Service interface but always returns an error.
func (n *NoOpClient) Synthesize(ctx context.Context, text string, voice string) ([]byte, error) {
	return nil, fmt.Errorf("tts: service not configured")
}

// SentenceSplitter splits text into sentences for streaming TTS.
// It looks for sentence-ending punctuation: . ! ? 。！？
type SentenceSplitter struct {
	buffer string
}

// NewSentenceSplitter creates a new sentence splitter.
func NewSentenceSplitter() *SentenceSplitter {
	return &SentenceSplitter{}
}

// AddText adds text to the buffer and returns any complete sentences.
func (s *SentenceSplitter) AddText(text string) []string {
	s.buffer += text
	return s.extractSentences()
}

// Flush returns any remaining text in the buffer as a sentence.
func (s *SentenceSplitter) Flush() string {
	result := s.buffer
	s.buffer = ""
	return result
}

// extractSentences extracts complete sentences from the buffer.
func (s *SentenceSplitter) extractSentences() []string {
	var sentences []string
	start := 0

	for i, r := range s.buffer {
		if isSentenceEnd(r) {
			sentence := s.buffer[start : i+1]
			if sentence != "" {
				sentences = append(sentences, sentence)
			}
			start = i + 1
		}
	}

	// Keep remaining incomplete text in buffer
	s.buffer = s.buffer[start:]
	return sentences
}

// isSentenceEnd checks if a rune is a sentence-ending punctuation.
func isSentenceEnd(r rune) bool {
	return r == '.' || r == '!' || r == '?' || r == '。' || r == '！' || r == '？' || r == '\n'
}
