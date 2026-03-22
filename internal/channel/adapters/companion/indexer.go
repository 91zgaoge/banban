package companion

import (
	"context"
	"log/slog"
	"strings"
	"time"

	"github.com/Kxiandaoyan/Memoh-v2/internal/db"
	dbsqlc "github.com/Kxiandaoyan/Memoh-v2/internal/db/sqlc"
	"github.com/Kxiandaoyan/Memoh-v2/internal/memory"
)

// Indexer asynchronously extracts memorable facts from companion conversations
// and stores them in the Qdrant memory store via memory.Service.
//
// It is called after each StreamEventFinal so that the full exchange
// (user question + assistant answer) is available for LLM-based extraction.
type Indexer struct {
	log       *slog.Logger
	memorySvc *memory.Service
	queries   *dbsqlc.Queries
}

// NewIndexer creates an Indexer backed by the given memory.Service and db queries.
func NewIndexer(log *slog.Logger, memorySvc *memory.Service, queries *dbsqlc.Queries) *Indexer {
	return &Indexer{
		log:       log.With(slog.String("component", "companion_indexer")),
		memorySvc: memorySvc,
		queries:   queries,
	}
}

// IndexAsync fires a goroutine to extract and store memories for one
// conversation turn. It is safe to call from any goroutine.
//
// Failures are logged as warnings; they do not affect the caller.
func (idx *Indexer) IndexAsync(_ context.Context, botID, userID, userText, assistantText string) {
	if botID == "" || userText == "" || assistantText == "" {
		return
	}
	idx.log.Info("companion indexer: queuing memory extraction",
		slog.String("bot_id", botID),
		slog.String("user_id", userID),
	)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		// Look up the bot's memory model to ensure we use the right LLM
		if idx.queries != nil {
			if pgBotID, parseErr := db.ParseUUID(botID); parseErr == nil {
				if settingsRow, sErr := idx.queries.GetSettingsByBotID(ctx, pgBotID); sErr == nil {
					if mid := strings.TrimSpace(settingsRow.MemoryModelID.String); mid != "" {
						ctx = memory.WithPreferredModel(ctx, mid)
					}
				}
			}
		}

		msgs := []memory.Message{
			{Role: "user", Content: userText},
			{Role: "assistant", Content: assistantText},
		}
		if _, err := idx.memorySvc.Add(ctx, memory.AddRequest{
			Messages: msgs,
			BotID:    botID,
			UserID:   userID,
			Filters:  map[string]any{"namespace": "companion"},
		}); err != nil {
			idx.log.Warn("companion memory indexing failed",
				slog.String("bot_id", botID),
				slog.String("user_id", userID),
				slog.String("error", err.Error()),
			)
		} else {
			idx.log.Info("companion memory indexed successfully",
				slog.String("bot_id", botID),
				slog.String("user_id", userID),
			)
		}
	}()
}
