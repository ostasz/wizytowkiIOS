import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

// Rate limiter configuration
// For MVP: Uses in-memory fallback if Upstash is not configured
// For production: Set UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN in Vercel env vars

let ratelimit: Ratelimit | null = null;

// In-memory fallback for MVP (resets on each deployment)
const inMemoryStore = new Map<string, { count: number; resetAt: number }>();

function getInMemoryRateLimit(key: string, limit: number, windowMs: number): boolean {
    const now = Date.now();
    const record = inMemoryStore.get(key);

    if (!record || now > record.resetAt) {
        inMemoryStore.set(key, { count: 1, resetAt: now + windowMs });
        return true;
    }

    if (record.count >= limit) {
        return false;
    }

    record.count++;
    return true;
}

// Initialize Upstash Redis if credentials are available
if (process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN) {
    const redis = new Redis({
        url: process.env.UPSTASH_REDIS_REST_URL,
        token: process.env.UPSTASH_REDIS_REST_TOKEN,
    });

    ratelimit = new Ratelimit({
        redis,
        limiter: Ratelimit.slidingWindow(10, "1 m"), // 10 requests per minute
        analytics: true,
    });

    console.log("✅ Rate limiting enabled with Upstash Redis");
} else {
    console.warn("⚠️ UPSTASH_REDIS not configured. Using in-memory rate limiting (MVP mode)");
}

export async function checkRateLimit(identifier: string): Promise<{ success: boolean; remaining?: number }> {
    if (ratelimit) {
        // Use Upstash Redis
        const result = await ratelimit.limit(identifier);
        return { success: result.success, remaining: result.remaining };
    } else {
        // Use in-memory fallback (10 requests per minute)
        const allowed = getInMemoryRateLimit(identifier, 10, 60000);
        return { success: allowed };
    }
}
