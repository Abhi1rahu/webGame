import { Router, Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

// Extended Request type to include user info from JWT
interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    email: string;
  };
}

// Initialize router
const router = Router();

// JWT Authentication Middleware
const authenticateJWT = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void => {
  const token = req.headers.authorization?.split(' ')[1];

  if (!token) {
    res.status(401).json({ error: 'No token provided' });
    return;
  }

  try {
    const secret = process.env.JWT_SECRET || 'your-secret-key';
    const decoded = jwt.verify(token, secret) as { id: string; email: string };
    req.user = decoded;
    next();
  } catch (error) {
    res.status(403).json({ error: 'Invalid or expired token' });
  }
};

// Mock database (replace with actual database calls)
interface Wallet {
  userId: string;
  balance: number;
}

interface Transaction {
  id: string;
  userId: string;
  type: 'deposit' | 'withdrawal';
  amount: number;
  timestamp: Date;
  status: 'completed' | 'pending' | 'failed';
  description?: string;
}

// In-memory storage (replace with actual database)
const wallets: Map<string, Wallet> = new Map();
const transactions: Transaction[] = [];

/**
 * GET /api/wallet/balance
 * Retrieve the current wallet balance for the authenticated user
 */
router.get('/balance', authenticateJWT, (req: AuthenticatedRequest, res: Response): void => {
  try {
    const userId = req.user?.id;
    
    if (!userId) {
      res.status(401).json({ error: 'User ID not found in token' });
      return;
    }

    const wallet = wallets.get(userId) || { userId, balance: 0 };
    
    res.status(200).json({
      success: true,
      data: {
        userId,
        balance: wallet.balance,
        currency: 'USD',
        lastUpdated: new Date(),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve wallet balance',
    });
  }
});

/**
 * POST /api/wallet/deposit
 * Deposit funds into the user's wallet
 * Body: { amount: number, paymentMethod?: string, description?: string }
 */
router.post('/deposit', authenticateJWT, (req: AuthenticatedRequest, res: Response): void => {
  try {
    const userId = req.user?.id;
    const { amount, paymentMethod = 'credit_card', description } = req.body;

    if (!userId) {
      res.status(401).json({ error: 'User ID not found in token' });
      return;
    }

    // Validation
    if (!amount || amount <= 0) {
      res.status(400).json({ error: 'Invalid amount. Must be greater than 0.' });
      return;
    }

    if (amount > 10000) {
      res.status(400).json({ error: 'Deposit amount exceeds maximum limit of $10,000' });
      return;
    }

    // Get or create wallet
    const wallet = wallets.get(userId) || { userId, balance: 0 };
    wallet.balance += amount;
    wallets.set(userId, wallet);

    // Record transaction
    const transaction: Transaction = {
      id: `TXN-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      userId,
      type: 'deposit',
      amount,
      timestamp: new Date(),
      status: 'completed',
      description: description || `Deposit via ${paymentMethod}`,
    };
    transactions.push(transaction);

    res.status(201).json({
      success: true,
      message: 'Deposit successful',
      data: {
        transactionId: transaction.id,
        amount,
        newBalance: wallet.balance,
        timestamp: transaction.timestamp,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Failed to process deposit',
    });
  }
});

/**
 * POST /api/wallet/withdrawal
 * Withdraw funds from the user's wallet
 * Body: { amount: number, withdrawalMethod?: string, description?: string }
 */
router.post('/withdrawal', authenticateJWT, (req: AuthenticatedRequest, res: Response): void => {
  try {
    const userId = req.user?.id;
    const { amount, withdrawalMethod = 'bank_transfer', description } = req.body;

    if (!userId) {
      res.status(401).json({ error: 'User ID not found in token' });
      return;
    }

    // Validation
    if (!amount || amount <= 0) {
      res.status(400).json({ error: 'Invalid amount. Must be greater than 0.' });
      return;
    }

    const wallet = wallets.get(userId) || { userId, balance: 0 };

    if (wallet.balance < amount) {
      res.status(400).json({
        error: 'Insufficient balance',
        currentBalance: wallet.balance,
        requestedAmount: amount,
      });
      return;
    }

    // Process withdrawal
    wallet.balance -= amount;
    wallets.set(userId, wallet);

    // Record transaction
    const transaction: Transaction = {
      id: `TXN-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      userId,
      type: 'withdrawal',
      amount,
      timestamp: new Date(),
      status: 'pending', // Withdrawals typically require processing time
      description: description || `Withdrawal to ${withdrawalMethod}`,
    };
    transactions.push(transaction);

    res.status(200).json({
      success: true,
      message: 'Withdrawal initiated',
      data: {
        transactionId: transaction.id,
        amount,
        newBalance: wallet.balance,
        status: transaction.status,
        estimatedCompletion: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000), // 2 days
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Failed to process withdrawal',
    });
  }
});

/**
 * GET /api/wallet/transactions
 * Retrieve transaction history for the authenticated user
 * Query params: ?limit=10&offset=0&type=all (deposit/withdrawal/all)
 */
router.get('/transactions', authenticateJWT, (req: AuthenticatedRequest, res: Response): void => {
  try {
    const userId = req.user?.id;
    const limit = parseInt(req.query.limit as string) || 10;
    const offset = parseInt(req.query.offset as string) || 0;
    const type = (req.query.type as string) || 'all';

    if (!userId) {
      res.status(401).json({ error: 'User ID not found in token' });
      return;
    }

    // Filter transactions for the user
    let userTransactions = transactions.filter((t) => t.userId === userId);

    // Filter by type if specified
    if (type !== 'all') {
      userTransactions = userTransactions.filter((t) => t.type === type);
    }

    // Sort by most recent first
    userTransactions.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

    // Pagination
    const totalCount = userTransactions.length;
    const paginatedTransactions = userTransactions.slice(offset, offset + limit);

    res.status(200).json({
      success: true,
      data: {
        transactions: paginatedTransactions,
        pagination: {
          total: totalCount,
          limit,
          offset,
          hasMore: offset + limit < totalCount,
        },
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve transaction history',
    });
  }
});

/**
 * GET /api/wallet/transactions/:transactionId
 * Retrieve details of a specific transaction
 */
router.get(
  '/transactions/:transactionId',
  authenticateJWT,
  (req: AuthenticatedRequest, res: Response): void => {
    try {
      const userId = req.user?.id;
      const { transactionId } = req.params;

      if (!userId) {
        res.status(401).json({ error: 'User ID not found in token' });
        return;
      }

      const transaction = transactions.find(
        (t) => t.id === transactionId && t.userId === userId
      );

      if (!transaction) {
        res.status(404).json({ error: 'Transaction not found' });
        return;
      }

      res.status(200).json({
        success: true,
        data: transaction,
      });
    } catch (error) {
      res.status(500).json({
        success: false,
        error: 'Failed to retrieve transaction details',
      });
    }
  }
);

export default router;
