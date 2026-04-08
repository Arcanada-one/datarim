---
name: testing
description: Testing pyramid, frameworks (Jest, Vitest, Playwright), and mocking rules. Use when writing or reviewing tests.
---

# Testing Guidelines

## Frameworks
- **Backend**: Jest / Mocha
- **Frontend**: Vitest / React Testing Library
- **E2E**: Playwright / Cypress

## Testing Pyramid
1.  **Unit Tests (70%)**: Test individual functions/classes in isolation. Mock all dependencies.
2.  **Integration Tests (20%)**: Test interaction between modules/database.
3.  **E2E Tests (10%)**: Test critical user flows.

## Mocking Rules
- Mock external APIs (Stripe, AWS, etc.).
- Mock database calls in unit tests.
- Use dependency injection to make mocking easier.
