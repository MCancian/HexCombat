---
title: "0017: Move Away from push_error for Validation"
status: "draft"
created: "2026-07-19"
---

# Plan 0017: Move Away from push_error for Validation

Currently, invalid orders (e.g., committing a destroyed brigade, moving beyond allowance) are rejected by calling `push_error()` with a specific string. 

This makes testing brittle (tests must regex-match `push_error` strings) and makes it difficult for the API (like the LLM JSON interface) to programmatically handle rejections or feed them back without parsing engine logs.

## Objectives
1. Define a standard `Result` type or a set of `Error` enums for order validation.
2. Update `OrderValidator` and other validation systems to return these errors instead of calling `push_error()`.
3. Update all GdUnit4 tests (`composition_test.gd`, `movement_test.gd`, etc.) to assert on the returned error instead of using `assert_error().is_push_error()`.
4. Ensure the LLM API gracefully surfaces these rejections back to the client/agent in the JSON interface.

## Verification
- Test suite logic should accurately reflect the new return types without losing test coverage on the rejection reasons.
- `tools/run_all_tests.py` must pass.
