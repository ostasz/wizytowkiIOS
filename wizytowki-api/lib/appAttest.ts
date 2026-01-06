import { NextRequest } from 'next/server';
import jwt from 'jsonwebtoken';

const TEAM_ID = 'JK6DX9TLGX';
const KEY_ID = '2NV4Y9L6ZT';
const BUNDLE_ID = 's.Wizytowki.Test1234';

/**
 * Verify App Attest token from iOS client
 * For MVP: We use a simplified JWT-based approach instead of full attestation flow
 * The iOS app signs requests with a device-specific token
 */
export async function verifyAppAttest(req: NextRequest): Promise<boolean> {
    try {
        const attestToken = req.headers.get('x-attest-token');

        if (!attestToken) {
            console.log('❌ Missing attest token');
            return false;
        }

        // Get the DeviceCheck private key from env
        const privateKey = process.env.DEVICECHECK_PRIVATE_KEY;

        if (!privateKey) {
            console.error('❌ DEVICECHECK_PRIVATE_KEY not configured');
            return false;
        }

        // Verify the JWT token
        // For production: implement full App Attest flow with challenge-response
        // For MVP: verify signature and basic claims
        const decoded = jwt.verify(attestToken, privateKey, {
            algorithms: ['ES256'],
            issuer: TEAM_ID,
        }) as any;

        // Verify bundle ID matches
        if (decoded.bundleId !== BUNDLE_ID) {
            console.log('❌ Bundle ID mismatch');
            return false;
        }

        console.log('✅ App Attest verified');
        return true;

    } catch (error) {
        console.error('❌ App Attest verification failed:', error);
        return false;
    }
}
