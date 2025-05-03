## 1.5.2
- Fixed the issue where windows support was not visible on Pub.dev
- Fixed wrong version number in readme.

## 1.5.1

- Enhanced Query API with improved type safety and fluent interface
  - Added method chaining with addWhere(), addOrderBy(), page(), limitTo(), offsetBy()
  - Added SortDirection enum for sorting control
  - Exported Query and WhereCondition classes in main package file
- Implemented SQL and in-memory filtering with getItemsWithQuery() and getModelsWithQuery()
- Added comprehensive Query API example documentation for various use cases
- Fixed compatibility issues with older query methods
- Translated all Turkish comments to English for better internationalization
- Fixed deprecation warnings in SyncEngine with Query API integration

## 1.5.0

- Enhanced Synchronization Strategies
  - Added three new customizable sync strategies:
    - `DeleteStrategy`: Control whether deletions are optimistic (local-first) or pessimistic (remote-first)
    - `FetchStrategy`: Configure how data is retrieved (background sync, remote-first, local with fallback, or local-only)
    - `SaveStrategy`: Manage save operations with optimistic or pessimistic approaches
  - Implemented proper handling of marked-for-deletion items in offline mode
  - Added generic result type support for improved type safety
  - Enhanced query capabilities with optional parameters
- Enhanced REST API Integration
  - Dynamic URL parameter replacement with `urlParameters` support
  - Request timeout customization via `timeoutMillis`
  - Automatic retry handling with `retryCount`
  - Custom response transformers with `responseTransformer`
  - Added `RestRequest` and `RestRequests` classes to customize API requests and responses
  - Support for custom request body formatting (wrapping data in top-level keys)
  - Support for adding supplemental data to request bodies
  - Support for extracting data from specific response fields
- Improved type safety with `RestMethod` enum instead of string literals
- Cross-platform support with sqflite_common_ffi
  - Added Windows and Linux platform support via sqflite_common_ffi
  - Created storage_helper for platform-specific SQLite initialization
  - Ensured consistent behavior across all platforms (Android, iOS, macOS, Windows, Linux)
- Internationalization improvements
  - English translation for all Turkish comments
  - Converted all comments to English for better international developer experience
  - Consistent code documentation across the codebase
- Updated example app demonstrating advanced request customization

- Fixed WebSocketNetworkClient implementation to correctly implement NetworkClient interface
- Fixed RestRequest handling in SyncRepositoryImpl
- Fixed handling of API responses with nested data structures
- Fixed issue with network error handling in example app
- Improved error messages and debugging information
- Enhanced example app with better offline capabilities

- Added cross-platform support (Windows/Linux) via sqflite_common_ffi
- Added mock API support for testing without real server
- Improved internationalization with English translations
- Fixed various bugs including API endpoint handling
- Added model-level sync strategy configuration
- Improved error handling

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