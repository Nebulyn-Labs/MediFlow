describe("Rate Limiter - RateLimiter Tests", () => {
  let rateLimiter;

  beforeAll(() => {
    rateLimiter = require("./rateLimiter");
  });

  test("LIMITS configuration exists", () => {
    expect(rateLimiter.LIMITS).toBeDefined();
    expect(rateLimiter.LIMITS.AI).toBeDefined();
    expect(rateLimiter.LIMITS.GENERAL).toBeDefined();
    expect(rateLimiter.LIMITS.AI.limit).toBe(20);
    expect(rateLimiter.LIMITS.AI.windowMs).toBe(60 * 60 * 1000);
    expect(rateLimiter.LIMITS.GENERAL.limit).toBe(100);
  });

  test("cleanupExpiredRateLimitRecords function exists", () => {
    expect(rateLimiter.cleanupExpiredRateLimitRecords).toBeInstanceOf(Function);
  });

  test("checkRateLimit function exists", () => {
    expect(rateLimiter.checkRateLimit).toBeInstanceOf(Function);
  });
});

describe("Rate Limiter - Cleanup Function Integration", () => {
  let rateLimiter;

  beforeAll(() => {
    rateLimiter = require("./rateLimiter");
  });

  test("cleanupExpiredRateLimitRecords has correct signature", () => {
    const fn = rateLimiter.cleanupExpiredRateLimitRecords;
    expect(fn).toBeInstanceOf(Function);
    expect(fn.length).toBe(0);
  });
});
