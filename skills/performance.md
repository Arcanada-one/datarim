---
name: performance
description: Optimization patterns (lazy loading, caching, batching), database and frontend performance. Use when designing or reviewing for performance.
---

# Performance Guidelines

## Optimization Patterns
- **Lazy Loading**: Load resources/modules only when needed.
- **Caching**: Use caching layers (Redis, Memory) for expensive operations.
- **Batching**: Batch database/API requests where possible.

## Database
- Ensure indexes exist on queried columns.
- Avoid N+1 query problems (use `include` or batch loading).

## Frontend
- Minimize bundle size.
- Optimize images (WebP, lazy load).
- Use virtualization for large lists.
