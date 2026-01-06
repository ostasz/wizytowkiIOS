import { NextRequest } from 'next/server';

const TEAM_ID = 'JK6DX9TLGX';
const BUNDLE_ID = 's.Wizytowki.Test1234';

/**
 * Verify App Attest token from iOS client
 * For MVP: Simplified approach - decode Base64 token and verify payload
 * Production: Should use full App Attest flow with cryptographic verification
 */
export async function verifyAppAttest(req: NextRequest): Promise<boolean> {
    try {
        const attestToken = req.headers.get('x-attest-token');

        if (!attestToken) {
            console.log('❌ Missing attest token');
            return false;
        }

        // Decode Base64 token
        const decoded = Buffer.from(attestToken, 'base64').toString('utf-8');
        const payload = JSON.parse(decoded);

        // Verify required fields
        if (!payload.deviceId || !payload.bundleId || !payload.timestamp) {
            console.log('❌ Invalid token payload');
            return false;
        }

        // Verify bundle ID matches
        if (payload.bundleId !== BUNDLE_ID) {
            console.log('❌ Bundle ID mismatch');
            return false;
        }

        // Verify Team ID
        if (payload.iss !== TEAM_ID) {
            console.log('❌ Team ID mismatch');
            return false;
        }

        // Verify timestamp is recent (within last 5 minutes)
        const now = Date.now() / 1000;
        const tokenAge = now - payload.timestamp;
        if (tokenAge > 300 || tokenAge < -60) {
            console.log('❌ Token expired or invalid timestamp');
            return false;
        }

        console.log('✅ App Attest verified for device:', payload.deviceId.substring(0, 8));
        return true;

    } catch (error) {
        console.error('❌ App Attest verification failed:', error);
        return false;
    }
}
