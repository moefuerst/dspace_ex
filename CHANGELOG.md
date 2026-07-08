# CHANGELOG

All notable changes to this project will be documented in this file.

## [v0.1.1] – 2026-07-08

  * Migrated the test suite from Bypass to Sham
  * Fixed a bug where the assetstore in the DSpace stack for external testing wasn't set up
    correctly
  * Fixed a bug where file uploads were not setting headers correctly
  * Fixed a bug where a logout operation would return an error struct even on success
  * Fixed a bug where response streaming would fail because of an incorrectly accepted request
    override option
  * Minor enhancements to the external tests
  * Various improvements to documentation

## [v0.1.0] – 2026-07-05

  * Item.create_draft/1 now accepts a :from option to create a draft from an external 
    source DSpace provides an integration for
  * Item.create/2 now adds sensible defaults for key fields unlikely to be customized by the 
    caller to the payload (such as "type" which will always be "item")
  * Add API.next_page/2
  * Add Github actions CI workflows 
  * Improve reliability of CSRF token parsing
  * Various improvements to documentation

Breaking changes:

  * Item.submit/3 now returns :published instead of :archived on success for more consistent 
    terminology throughout the codebase.

## [v0.1.0-alpha2] – 2026-07-01

  * Initialize from proof of concept repo
  * Hex package setup
