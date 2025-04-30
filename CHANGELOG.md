## 1.4.0

* WebSocket Support and Real-Time Synchronization:
  * Added **WebSocketConnectionManager** - Manages WebSocket connection lifecycle, reconnection attempts, and status notifications
  * Added **WebSocketNetworkClient** - Provides WebSocket-based alternative alongside Http-based network client
  * Added **WebSocketConfig** - Comprehensive configuration options for WebSocket behavior
  * Added **SyncEventMapper** class - Maps WebSocket event names and SyncEventType enumeration
  * Pub/sub messaging system for subscriptions and channel listening

* Customization Enhancements:
  * Support for multiple message formatters for customizable message format
  * Advanced hooks for connection lifecycle management and status monitoring
  * Extensible behavior for WebSocket connection handling
  * Customizable ping/pong messages

* Event System Improvements:
  * Extended SyncEventType for tracking and listening to synchronization events
  * Client-side event filtering and transformation capabilities
  * Enhanced support for event listeners and stream creation

## 1.3.0

* Custom repository support:
  * Added customRepository parameter to OfflineSyncManager.initialize()
  * Repository can now be accessed via new getter in SyncEngine
  * Improved syncItemDelta to better support custom implementations
* Model factory handling:
  * fetchItems and pullFromServer now correctly use registered model factories
  * Fixed issue where modelFactories was null in custom repositories
  * modelFactories are now passed into fetchItems from pullFromServer
* Delta sync improvements:
  * SyncModel.toJsonDelta() made more reliable and consistent
* Error handling improvements:
  * Better handling of invalid or unexpected API responses
  * Safer defaults applied when responses are incomplete

## 1.2.0

* Added github address to pubspec.yaml file.
* Readme file updated.

## 1.1.0

* Advanced conflict resolution strategies:
  * Server-wins, client-wins, last-update-wins policies
  * Custom conflict resolution handler support
  * Conflict detection and reporting
* Delta synchronization:
  * Optimized syncing of changed fields only
  * Automatic tracking of field-level changes
  * Reduced network bandwidth usage
* Optional data encryption:
  * Secure storage of sensitive information
  * Configurable encryption keys
  * Transparent encryption/decryption process
* Performance optimizations:
  * Batched synchronization support
  * Prioritized sync queue management
  * Enhanced offline processing
* Extended configuration options:
  * Flexible synchronization intervals
  * Custom batch size settings
  * Bidirectional sync controls

## 1.0.0

* Initial official release
* Core features:
  * Flexible data model integration based on SyncModel
  * Offline data storage with local database
  * Automatic data synchronization
  * Internet connectivity monitoring
  * Synchronization status tracking
  * Exponential backoff retry mechanism
  * Bidirectional synchronization support
  * Data conflict management
  * Customizable API integration
* Example application demonstrating usage
* SQLite-based StorageServiceImpl implementation
* HTTP-based DefaultNetworkClient implementation
* Comprehensive documentation