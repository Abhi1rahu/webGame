import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class GameScreen extends StatefulWidget {
  final String gameId;
  final String playerId;
  final String socketUrl;

  const GameScreen({
    Key? key,
    required this.gameId,
    required this.playerId,
    required this.socketUrl,
  }) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late IO.Socket socket;
  int score = 0;
  String gameStatus = 'Waiting...';
  bool isGameActive = false;
  bool isTapEnabled = true;
  int tapCount = 0;
  Map<String, dynamic> playerStats = {};
  int gameTimeRemaining = 60;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeSocket();
  }

  void _initializeSocket() {
    try {
      socket = IO.io(
        widget.socketUrl,
        IO.SocketIoClientOptions(
          transports: ['websocket'],
          autoConnect: true,
          reconnection: true,
          reconnectionDelay: const Duration(seconds: 1),
          reconnectionAttempts: 10,
        ),
      );

      // Socket connection events
      socket.on('connect', (_) {
        setState(() {
          isConnected = true;
          gameStatus = 'Connected!';
        });
        debugPrint('Socket connected: ${socket.id}');
        _joinGame();
      });

      socket.on('disconnect', (_) {
        setState(() {
          isConnected = false;
          gameStatus = 'Disconnected';
          isGameActive = false;
        });
        debugPrint('Socket disconnected');
      });

      socket.on('connect_error', (error) {
        setState(() {
          gameStatus = 'Connection Error';
        });
        debugPrint('Connection error: $error');
      });

      // Game-specific events
      socket.on('gameStarted', (data) {
        setState(() {
          isGameActive = true;
          gameStatus = 'Game Started!';
          gameTimeRemaining = data['duration'] ?? 60;
          score = 0;
          tapCount = 0;
        });
        debugPrint('Game started: $data');
        _startGameTimer();
      });

      socket.on('gameEnded', (data) {
        setState(() {
          isGameActive = false;
          isTapEnabled = false;
          gameStatus = 'Game Over!';
          playerStats = data;
        });
        debugPrint('Game ended: $data');
        _showGameOverDialog();
      });

      socket.on('tapConfirmed', (data) {
        setState(() {
          score = data['score'] ?? 0;
          tapCount = data['tapCount'] ?? 0;
        });
        debugPrint('Tap confirmed - Score: $score, Taps: $tapCount');
      });

      socket.on('playerStats', (data) {
        setState(() {
          playerStats = data;
        });
        debugPrint('Player stats updated: $data');
      });

      socket.on('gameStatus', (data) {
        setState(() {
          gameStatus = data['status'] ?? 'Ready';
        });
        debugPrint('Game status: ${data['status']}');
      });

      socket.on('error', (error) {
        setState(() {
          gameStatus = 'Error: $error';
        });
        debugPrint('Socket error: $error');
      });

      socket.connect();
    } catch (e) {
      debugPrint('Error initializing socket: $e');
      setState(() {
        gameStatus = 'Failed to connect';
      });
    }
  }

  void _joinGame() {
    socket.emit('joinGame', {
      'gameId': widget.gameId,
      'playerId': widget.playerId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _handleTap() {
    if (!isGameActive || !isTapEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isGameActive ? 'Tap too fast!' : 'Game not active'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() {
      isTapEnabled = false;
      tapCount++;
    });

    // Send tap event to server
    socket.emit('tap', {
      'gameId': widget.gameId,
      'playerId': widget.playerId,
      'timestamp': DateTime.now().toIso8601String(),
      'tapCount': tapCount,
    });

    // Re-enable tap after a short delay (tap rate limit)
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && isGameActive) {
        setState(() {
          isTapEnabled = true;
        });
      }
    });
  }

  void _startGameTimer() {
    Future.doWhile(() async {
      if (!mounted || !isGameActive) return false;

      await Future.delayed(const Duration(seconds: 1));

      if (mounted && isGameActive) {
        setState(() {
          gameTimeRemaining--;
          if (gameTimeRemaining <= 0) {
            isGameActive = false;
            return false;
          }
        });
      }
      return isGameActive;
    });
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Game Over!'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Final Score: $score',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text('Total Taps: $tapCount'),
              const SizedBox(height: 8),
              if (playerStats.isNotEmpty) ...[
                Text('Rank: #${playerStats['rank'] ?? 'N/A'}'),
                const SizedBox(height: 8),
                Text('Avg Tap Rate: ${playerStats['avgTapRate']?.toStringAsFixed(2) ?? 'N/A'} taps/sec'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetGame();
            },
            child: const Text('Play Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  void _resetGame() {
    setState(() {
      score = 0;
      tapCount = 0;
      gameStatus = 'Waiting...';
      isGameActive = false;
      isTapEnabled = true;
      gameTimeRemaining = 60;
      playerStats = {};
    });
    _joinGame();
  }

  @override
  void dispose() {
    socket.disconnect();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tap Race Game'),
        elevation: 0,
        backgroundColor: Colors.deepPurple,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    isConnected ? Icons.cloud_done : Icons.cloud_off,
                    color: isConnected ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected ? 'Connected' : 'Offline',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.deepPurple.shade800, Colors.purple.shade600],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Status Section
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Text(
                      gameStatus,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Time: ${gameTimeRemaining}s',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Score Display
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'SCORE',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        '$score',
                        style: const TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Taps: $tapCount',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Tap Button
              Padding(
                padding: const EdgeInsets.all(40.0),
                child: GestureDetector(
                  onTap: isGameActive ? _handleTap : null,
                  child: Container(
                    height: 120,
                    width: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isGameActive ? Colors.amber : Colors.grey,
                      boxShadow: [
                        BoxShadow(
                          color: isGameActive ? Colors.amber.withOpacity(0.5) : Colors.grey.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: isGameActive ? _handleTap : null,
                        customBorder: const CircleBorder(),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.touch_app,
                                size: 40,
                                color: isGameActive ? Colors.white : Colors.white54,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isGameActive ? 'TAP' : 'WAIT',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isGameActive ? Colors.white : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
