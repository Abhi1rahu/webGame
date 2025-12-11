import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'dart:convert';

class LobbyScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String backendUrl;

  const LobbyScreen({
    required this.userId,
    required this.userName,
    required this.backendUrl,
    Key? key,
  }) : super(key: key);

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late IO.Socket socket;
  List<Game> games = [];
  bool isLoading = true;
  bool isSocketConnected = false;
  String? errorMessage;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeSocket();
    _fetchGames();
  }

  void _initializeSocket() {
    socket = IO.io(widget.backendUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnectionDelay': 1000,
      'reconnection': true,
      'reconnectionAttempts': 5,
    });

    socket.on('connect', (_) {
      print('Socket connected');
      setState(() {
        isSocketConnected = true;
      });
      _emitJoinLobby();
    });

    socket.on('gameListUpdated', (data) {
      print('Game list updated: $data');
      _parseGames(data);
    });

    socket.on('gameCreated', (data) {
      print('New game created: $data');
      if (mounted) {
        setState(() {
          final newGame = Game.fromJson(data);
          games.insert(0, newGame);
        });
      }
    });

    socket.on('gameRemoved', (data) {
      print('Game removed: $data');
      if (mounted) {
        setState(() {
          games.removeWhere((game) => game.id == data['gameId']);
        });
      }
    });

    socket.on('joinSuccess', (data) {
      print('Successfully joined game: $data');
      _showSuccessSnackbar('Joined game successfully!');
      Navigator.of(context).pushNamed(
        '/game',
        arguments: {
          'gameId': data['gameId'],
          'matchId': data['matchId'],
        },
      );
    });

    socket.on('joinError', (data) {
      print('Error joining game: $data');
      _showErrorSnackbar(data['message'] ?? 'Failed to join game');
    });

    socket.on('disconnect', (_) {
      print('Socket disconnected');
      setState(() {
        isSocketConnected = false;
      });
    });

    socket.on('error', (error) {
      print('Socket error: $error');
      setState(() {
        errorMessage = 'Connection error: $error';
      });
    });
  }

  void _emitJoinLobby() {
    socket.emit('joinLobby', {
      'userId': widget.userId,
      'userName': widget.userName,
    });
  }

  Future<void> _fetchGames() async {
    try {
      final response = await http
          .get(Uri.parse('${widget.backendUrl}/api/games'))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('Request timeout', 408),
          );

      if (response.statusCode == 200) {
        _parseGames(jsonDecode(response.body));
      } else {
        setState(() {
          errorMessage = 'Failed to fetch games (${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error fetching games: $e';
        isLoading = false;
      });
    }
  }

  void _parseGames(dynamic data) {
    try {
      final List<dynamic> gameList = data is List ? data : data['games'] ?? [];
      setState(() {
        games = gameList.map((game) => Game.fromJson(game)).toList();
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error parsing games: $e';
        isLoading = false;
      });
    }
  }

  void _joinGame(Game game) {
    if (!isSocketConnected) {
      _showErrorSnackbar('Not connected to server. Please try again.');
      return;
    }

    socket.emit('joinGame', {
      'userId': widget.userId,
      'gameId': game.id,
      'userName': widget.userName,
    });
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccessSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _refreshGames() {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    _fetchGames();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    socket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Lobby'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Chip(
                avatar: CircleAvatar(
                  backgroundColor:
                      isSocketConnected ? Colors.green : Colors.red,
                  radius: 3,
                ),
                label: Text(
                  isSocketConnected ? 'Connected' : 'Disconnected',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshGames();
          await Future.delayed(const Duration(seconds: 1));
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading && games.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null && games.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshGames,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (games.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.games, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No games available',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshGames,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final game = games[index];
        return GameCard(
          game: game,
          onJoin: () => _joinGame(game),
          isConnected: isSocketConnected,
        );
      },
    );
  }
}

class Game {
  final String id;
  final String name;
  final String description;
  final int maxPlayers;
  final int currentPlayers;
  final String gameType;
  final String status;
  final String createdBy;
  final DateTime createdAt;

  Game({
    required this.id,
    required this.name,
    required this.description,
    required this.maxPlayers,
    required this.currentPlayers,
    required this.gameType,
    required this.status,
    required this.createdBy,
    required this.createdAt,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'] ?? 'Unnamed Game',
      description: json['description'] ?? '',
      maxPlayers: json['maxPlayers'] ?? 2,
      currentPlayers: json['currentPlayers'] ?? 1,
      gameType: json['gameType'] ?? 'unknown',
      status: json['status'] ?? 'waiting',
      createdBy: json['createdBy'] ?? 'Unknown',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

class GameCard extends StatelessWidget {
  final Game game;
  final VoidCallback onJoin;
  final bool isConnected;

  const GameCard({
    required this.game,
    required this.onJoin,
    required this.isConnected,
    Key? key,
  }) : super(key: key);

  bool get isFull => game.currentPlayers >= game.maxPlayers;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: _getStatusColor(),
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Type: ${game.gameType}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${game.currentPlayers}/${game.maxPlayers}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (game.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      game.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Host: ${game.createdBy}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Status: ${game.status}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed:
                          (isFull || !isConnected) ? null : onJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFull ? Colors.grey : Colors.blue,
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                      child: Text(
                        isFull ? 'Full' : 'Join',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (game.status.toLowerCase()) {
      case 'waiting':
        return Colors.blue;
      case 'playing':
        return Colors.green;
      case 'finished':
        return Colors.grey;
      default:
        return Colors.purple;
    }
  }
}
