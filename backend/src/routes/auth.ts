import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { v4 as uuidv4 } from 'uuid';

const router = Router();

// Type definitions
interface SignupRequest {
  email: string;
  password: string;
  name: string;
}

interface LoginRequest {
  email: string;
  password: string;
}

interface OTPVerificationRequest {
  email: string;
  otp: string;
}

interface User {
  id: string;
  email: string;
  name: string;
  passwordHash: string;
  isVerified: boolean;
  createdAt: Date;
}

// In-memory storage (replace with database in production)
const users: Map<string, User> = new Map();
const otpStore: Map<string, { otp: string; expiresAt: Date }> = new Map();

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';
const JWT_EXPIRY = '7d';
const OTP_EXPIRY = 5 * 60 * 1000; // 5 minutes

/**
 * Helper function to generate OTP
 */
function generateOTP(): string {
  return Math.random().toString().slice(2, 8);
}

/**
 * Helper function to send OTP (mock implementation)
 */
async function sendOTP(email: string, otp: string): Promise<void> {
  // TODO: Implement actual email sending service (e.g., SendGrid, Nodemailer)
  console.log(`[OTP] Sending OTP ${otp} to ${email}`);
  // In production, use an email service like:
  // await emailService.sendOTP(email, otp);
}

/**
 * POST /auth/signup
 * Register a new user and send OTP for verification
 */
router.post('/signup', async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, password, name }: SignupRequest = req.body;

    // Validate input
    if (!email || !password || !name) {
      res.status(400).json({
        success: false,
        message: 'Email, password, and name are required',
      });
      return;
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      res.status(400).json({
        success: false,
        message: 'Invalid email format',
      });
      return;
    }

    // Validate password strength
    if (password.length < 8) {
      res.status(400).json({
        success: false,
        message: 'Password must be at least 8 characters long',
      });
      return;
    }

    // Check if user already exists
    const existingUser = Array.from(users.values()).find(
      (user) => user.email === email
    );
    if (existingUser) {
      res.status(409).json({
        success: false,
        message: 'User with this email already exists',
      });
      return;
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Create user
    const userId = uuidv4();
    const newUser: User = {
      id: userId,
      email,
      name,
      passwordHash,
      isVerified: false,
      createdAt: new Date(),
    };

    users.set(userId, newUser);

    // Generate and send OTP
    const otp = generateOTP();
    otpStore.set(email, {
      otp,
      expiresAt: new Date(Date.now() + OTP_EXPIRY),
    });

    await sendOTP(email, otp);

    res.status(201).json({
      success: true,
      message: 'User registered successfully. OTP sent to your email.',
      data: {
        userId,
        email,
        name,
      },
    });
  } catch (error) {
    console.error('Signup error:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error during signup',
    });
  }
});

/**
 * POST /auth/verify-otp
 * Verify OTP and mark user as verified
 */
router.post('/verify-otp', async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, otp }: OTPVerificationRequest = req.body;

    // Validate input
    if (!email || !otp) {
      res.status(400).json({
        success: false,
        message: 'Email and OTP are required',
      });
      return;
    }

    // Check if OTP exists and is valid
    const storedOTP = otpStore.get(email);
    if (!storedOTP) {
      res.status(404).json({
        success: false,
        message: 'OTP not found or expired',
      });
      return;
    }

    // Check if OTP is expired
    if (new Date() > storedOTP.expiresAt) {
      otpStore.delete(email);
      res.status(400).json({
        success: false,
        message: 'OTP has expired',
      });
      return;
    }

    // Verify OTP
    if (storedOTP.otp !== otp) {
      res.status(401).json({
        success: false,
        message: 'Invalid OTP',
      });
      return;
    }

    // Find and update user
    const user = Array.from(users.values()).find((u) => u.email === email);
    if (!user) {
      res.status(404).json({
        success: false,
        message: 'User not found',
      });
      return;
    }

    user.isVerified = true;
    otpStore.delete(email);

    // Generate JWT token
    const token = jwt.sign(
      {
        userId: user.id,
        email: user.email,
        name: user.name,
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    res.status(200).json({
      success: true,
      message: 'OTP verified successfully',
      data: {
        userId: user.id,
        email: user.email,
        name: user.name,
        token,
      },
    });
  } catch (error) {
    console.error('OTP verification error:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error during OTP verification',
    });
  }
});

/**
 * POST /auth/login
 * Login with email and password, return JWT token
 */
router.post('/login', async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, password }: LoginRequest = req.body;

    // Validate input
    if (!email || !password) {
      res.status(400).json({
        success: false,
        message: 'Email and password are required',
      });
      return;
    }

    // Find user
    const user = Array.from(users.values()).find((u) => u.email === email);
    if (!user) {
      res.status(401).json({
        success: false,
        message: 'Invalid email or password',
      });
      return;
    }

    // Check if user is verified
    if (!user.isVerified) {
      res.status(403).json({
        success: false,
        message: 'User account is not verified. Please verify your email first.',
      });
      return;
    }

    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.passwordHash);
    if (!isPasswordValid) {
      res.status(401).json({
        success: false,
        message: 'Invalid email or password',
      });
      return;
    }

    // Generate JWT token
    const token = jwt.sign(
      {
        userId: user.id,
        email: user.email,
        name: user.name,
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    res.status(200).json({
      success: true,
      message: 'Login successful',
      data: {
        userId: user.id,
        email: user.email,
        name: user.name,
        token,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error during login',
    });
  }
});

/**
 * POST /auth/refresh-token
 * Refresh JWT token
 */
router.post('/refresh-token', (req: Request, res: Response): void => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      res.status(401).json({
        success: false,
        message: 'Authorization header is missing',
      });
      return;
    }

    const token = authHeader.split(' ')[1];
    if (!token) {
      res.status(401).json({
        success: false,
        message: 'Token is missing',
      });
      return;
    }

    // Verify and decode token
    const decoded = jwt.verify(token, JWT_SECRET) as {
      userId: string;
      email: string;
      name: string;
    };

    // Generate new token
    const newToken = jwt.sign(
      {
        userId: decoded.userId,
        email: decoded.email,
        name: decoded.name,
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    res.status(200).json({
      success: true,
      message: 'Token refreshed successfully',
      data: {
        token: newToken,
      },
    });
  } catch (error) {
    console.error('Token refresh error:', error);
    res.status(401).json({
      success: false,
      message: 'Invalid or expired token',
    });
  }
});

export default router;
