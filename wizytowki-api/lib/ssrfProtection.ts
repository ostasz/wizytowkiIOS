import { lookup } from 'dns/promises';

/**
 * SSRF Protection Utility
 * Validates URLs to prevent Server-Side Request Forgery attacks
 */

// Private IP ranges (RFC 1918 + loopback + link-local)
const PRIVATE_IP_RANGES = [
    /^127\./,           // Loopback
    /^10\./,            // Private Class A
    /^172\.(1[6-9]|2[0-9]|3[0-1])\./,  // Private Class B
    /^192\.168\./,      // Private Class C
    /^169\.254\./,      // Link-local
    /^0\.0\.0\.0$/,     // Unspecified
    /^::1$/,            // IPv6 loopback
    /^fe80:/,           // IPv6 link-local
    /^fc00:/,           // IPv6 unique local
];

const BLOCKED_HOSTNAMES = [
    'localhost',
    'metadata.google.internal',  // GCP metadata
    'instance-data',             // AWS metadata (old)
];

function isPrivateIP(ip: string): boolean {
    return PRIVATE_IP_RANGES.some(range => range.test(ip));
}

function isBlockedHostname(hostname: string): boolean {
    const lower = hostname.toLowerCase();
    return BLOCKED_HOSTNAMES.some(blocked => lower.includes(blocked));
}

export async function validateAndSanitizeURL(url: string): Promise<{ valid: boolean; sanitized?: string; error?: string }> {
    try {
        // 1. Basic format validation
        if (!url || typeof url !== 'string') {
            return { valid: false, error: 'Invalid URL format' };
        }

        // 2. Force HTTPS only
        let sanitized = url.trim();
        if (!sanitized.startsWith('https://')) {
            if (sanitized.startsWith('http://')) {
                return { valid: false, error: 'Only HTTPS URLs are allowed' };
            }
            sanitized = `https://${sanitized}`;
        }

        // 3. Parse URL
        let parsed: URL;
        try {
            parsed = new URL(sanitized);
        } catch (e) {
            return { valid: false, error: 'Malformed URL' };
        }

        // 4. Check protocol (double-check)
        if (parsed.protocol !== 'https:') {
            return { valid: false, error: 'Only HTTPS protocol is allowed' };
        }

        // 5. Block credentials in URL
        if (parsed.username || parsed.password) {
            return { valid: false, error: 'URLs with credentials are not allowed' };
        }

        // 6. Check hostname
        const hostname = parsed.hostname.toLowerCase();

        // Block localhost variants
        if (isBlockedHostname(hostname)) {
            return { valid: false, error: 'Blocked hostname' };
        }

        // Block IP addresses directly (force domain names)
        const ipPattern = /^(\d{1,3}\.){3}\d{1,3}$/;
        if (ipPattern.test(hostname)) {
            return { valid: false, error: 'Direct IP addresses are not allowed. Use domain names.' };
        }

        // 7. DNS lookup to check resolved IP
        try {
            const addresses = await lookup(hostname, { all: true });

            for (const addr of addresses) {
                if (isPrivateIP(addr.address)) {
                    return { valid: false, error: 'URL resolves to private IP address' };
                }
            }
        } catch (dnsError) {
            return { valid: false, error: 'DNS lookup failed' };
        }

        // 8. All checks passed
        return { valid: true, sanitized };

    } catch (error) {
        return { valid: false, error: 'URL validation failed' };
    }
}

/**
 * Fetch with SSRF protection and size limits
 */
export async function safeFetch(url: string, maxSizeBytes: number = 2 * 1024 * 1024): Promise<{ ok: boolean; text?: string; error?: string }> {
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000); // 5s timeout

        const response = await fetch(url, {
            signal: controller.signal,
            redirect: 'manual', // Don't follow redirects (SSRF protection)
            headers: {
                'User-Agent': 'Mozilla/5.0 (Compatible; WizytownikAI/1.0)'
            }
        });

        clearTimeout(timeoutId);

        // Check for redirects (3xx status codes)
        if (response.status >= 300 && response.status < 400) {
            return { ok: false, error: 'Redirects are not allowed' };
        }

        if (!response.ok) {
            return { ok: false, error: `HTTP ${response.status}` };
        }

        // Stream response with size limit
        const reader = response.body?.getReader();
        if (!reader) {
            return { ok: false, error: 'No response body' };
        }

        const chunks: Uint8Array[] = [];
        let totalSize = 0;

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            totalSize += value.length;
            if (totalSize > maxSizeBytes) {
                reader.cancel();
                return { ok: false, error: 'Response too large (max 2MB)' };
            }

            chunks.push(value);
        }

        const buffer = Buffer.concat(chunks);
        const text = buffer.toString('utf-8');

        return { ok: true, text };

    } catch (error: any) {
        if (error.name === 'AbortError') {
            return { ok: false, error: 'Request timeout' };
        }
        return { ok: false, error: 'Fetch failed' };
    }
}
