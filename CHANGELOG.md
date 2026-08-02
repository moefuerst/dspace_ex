# CHANGELOG

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

  * Added `File.access_status/1` to fetch the access status of a file. This operation is 
    compatible with DSpace 9 and up
  * Added `ResourceUpdate` struct to represent an update to be performed on a resource
  * Core Resources' `update/3` functions and other functions that update resources now also
    accept `ResourceUpdate` structs besides plain maps
  * Added `Version` struct to represent an API compatibility target
  * Added `Operation.Error` struct which is returned when `Operation.perform/3` detects an
    operation would fail because the targeted DSpace instance would not support it or the client
    configuration would be insufficient to execute the operation successfully
  * Added `API.put_cris_version/2` to update the struct with a CRIS fork version string
  * Added `API.load_version/1` to update the struct with version information from the server
  * Added a `:lang` option to `Item.fetch/2` to specify the preferred return language for metadata
    values. The default (all languages) was chosen to work around a
    [bug](https://github.com/DSpace/DSpace/issues/12636) imported from the CRIS fork into DSpace
    recently. Impact should be minimal in most scenarios (where items do not have metadata
    explicitly stored in many languages), the `"allLanguages"` projection requested is more
    performant server-side since it skips language filtering logic (Thanks, Luca!)
  * Added `t:Resource.preferred_language/0` to represent the preferred language for metadata when 
    retrieving a resource.
  * Added `Transform.not_found_on_no_content/2` to transform 204 responses into 404 errors for 
    endpoints that conceptually fetch a single resource but are implemented as "searches" and thus
    return an empty result instead of a not found error
  * Added `Operation.JSON.put_param/2`, `Operation.JSON.put_header/2`, and 
    `Operation.JSON.put_lang/2` to update JSON operation structs
  * Added a `Model` behaviour with encoding functionality for resource types to prepare supporting
    more specific data structures for API resources in a future release
  * Query params are now included in the URI struct that is used for the `request_url` field of
    `HTTP.Response`, `HTTP.Error`, and `API.Error` structs for better debugging and logging
  
### Changed

  * `Item.fetch/2` now returns metadata in all languages by default
  * `Item.submit/2` has been renamed to `Item.submit_draft/2` for naming consistency
  * `Item.parent/1` has been renamed to `Item.fetch_parent/1` for naming consistency
  * `User.fetch_by_email/1` now returns a `:not_found` `API.Error` instead of an empty map if no
    user exists with the given email
  * `Community.fetch_parent/1` now returns a `:not_found` `API.Error` instead of an empty map if 
    the given community doesn't have a parent
  * A value for `api_version` in the `API` struct will prevent operations from making requests to
    the server if the operation is not supported and return an `Operation.Error` instead
  * The `API` struct now includes a `cris_version` field
  * The `Operation.JSON` struct now includes a `supported_versions` field
  * Type `t:Resource.resource_update/0` has been renamed to `t:Resource.update/0`
  * Module `Metadata.Value` has been renamed to `Model.MetadataValue`
  * `MetadataValue.placeholder/0` and `MetadataValue.placeholder?/0` have been replaced with
    `MetadataValue.placeholder/1` and `MetadataValue.placeholder?/1` to optionally allow setting a 
    custom placeholder text value. The default placeholder value used by the DSpace community 
    editions is used when no custom value is provided.
  * `tokens_from_response/1`, `token_from_response/1`, `access_token_from_response/1` and 
    `csrf_token_from_response/1` have been moved from the `Auth` to the `Transform` module  

### Removed

  * The `API` struct does not contain a default value for `api_version` anymore

### Documentation

  * Added a section that explains version compatibility configuration to the `API` struct
  * Various improvements to documentation

### Development

  * External tests that assert known buggy DSpace behavior are now tagged with `@bug` 
  * External tests that require the DSpace server to be able to connect to live third-party APIs 
    during test runs are now tagged with `:requires_third_party_api` to filter them out in 
    environments that do not have access to the Internet 
  * Introduced a 10d dependency cooldown
  * Various enhancements to the test suite
  * Various improvements to CI workflows


## [v0.1.1] – 2026-07-08

### Fixed

  * Fixed a bug where file uploads were not setting headers correctly
  * Fixed a bug where a logout operation could return an error struct even on success
  * Fixed a bug where response streaming could fail because of an incorrectly accepted request
    override option
 
### Documentation

  * Various improvements to documentation

### Development

  * Fixed a bug where the assetstore in the DSpace stack for external testing wasn't set up
    correctly
  * Migrated the test suite from Bypass to Sham
  * Minor enhancements to the external tests


## [v0.1.0] – 2026-07-05

### Added

  * Added `API.next_page/2` helper function
  * `Item.create_draft/1` now accepts a `:from` option to create a draft from an external 
    source DSpace provides an integration for
  * `Item.create/2` now adds sensible defaults for key fields unlikely to be customized by the 
    caller to the payload (such as `type` which will always be `item`) 

### Changed

  * `Item.submit/3` now returns `:published` instead of `:archived` on success for more consistent 
    terminology throughout the codebase.
  * Improved reliability of CSRF token parsing

### Documentation

  * Various improvements to documentation

## Development

  * Added Github actions CI workflows


## [v0.1.0-alpha2] – 2026-07-01

### Added

  * Initialize from proof of concept repo

### Development

  * Hex package setup


[Unreleased]: https://github.com/moefuerst/dspace_ex/compare/v0.1.1...HEAD
[v0.1.1]: https://github.com/moefuerst/dspace_ex/compare/v0.1.0...v0.1.1
[v0.1.0]: https://github.com/moefuerst/dspace_ex/compare/v0.1.0-alpha2...v0.1.0
[v0.1.0-alpha2]: https://github.com/moefuerst/dspace_ex/releases/tag/v0.1.0-alpha2
