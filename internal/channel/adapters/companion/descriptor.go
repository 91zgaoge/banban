// Package companion provides the Companion channel adapter for the BanBan AI companion platform.
// It enables real-time bidirectional communication between the Flutter companion app and the
// bot engine via WebSocket connections.
//
// Architecture:
//
//	Flutter App (WebSocket)
//	    ↓
//	CompanionHandler (HTTP upgrade → WS)
//	    ↓  registers session in SessionHub
//	channelManager.HandleInbound(botID, sessionID)
//	    ↓
//	Conversation Flow → Agent SSE
//	    ↓
//	CompanionAdapter.OpenStream(target=sessionID)
//	    ↓
//	wsOutboundStream.Push() → write JSON frames to WS conn
//	    ↓
//	Flutter App receives delta/final frames
package companion

import "github.com/Kxiandaoyan/Memoh-v2/internal/channel"

// CompanionType is the registered ChannelType for the Companion adapter.
const CompanionType channel.ChannelType = "companion"
