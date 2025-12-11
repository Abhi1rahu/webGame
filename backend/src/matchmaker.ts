import { Server, Socket } from 'socket.io';
import { v4 as uuidv4 } from 'uuid';

interface Player {
  id: string;
  socketId: string;
  username: string;
  taps: number;
  isReady: boolean;
  lastTapTimestamp: number;
  validatedTaps: number;
}

interface GameMatch {
  id: string;
  players: Map<string, Player>;
  status: 'waiting' | 'starting' | 'active' | 'finished';
  startTime: number | null;
  endTime: number | null;
  duration: number; // in milliseconds
  winner: string | null;
}

interface Queue {
  players: Map<string, Player>;
}

export class TapRaceMatchmaker {
  private io: Server;
  private matches: Map<string, GameMatch> = new Map();
  private queue: Queue = { players: new Map() };
  private playerToMatch: Map<string, string> = new Map(); // playerId -> matchId
  private playerQueue: Map<string, string> = new Map(); // playerId -> queueId
  private readonly MATCH_SIZE = 2;
  private readonly MATCH_DURATION = 30000; // 30 seconds
  private readonly TAP_VALIDATION_WINDOW = 100; // milliseconds
  private readonly MAX_TAPS_PER_SECOND = 10; // anti-cheat validation

  constructor(io: Server) {
    this.io = io;
    this.setupEventHandlers();
  }

  private setupEventHandlers(): void {
    this.io.on('connection', (socket: Socket) => {
      console.log(`Player connected: ${socket.id}`);

      socket.on('join_queue', (data: { userId: string; username: string }) => {
        this.handleJoinQueue(socket, data);
      });

      socket.on('leave_queue', (data: { userId: string }) => {
        this.handleLeaveQueue(socket, data);
      });

      socket.on('player_ready', (data: { userId: string; matchId: string }) => {
        this.handlePlayerReady(socket, data);
      });

      socket.on('tap', (data: { userId: string; matchId: string; timestamp: number }) => {
        this.handleTap(socket, data);
      });

      socket.on('disconnect', () => {
        this.handleDisconnect(socket);
      });
    });
  }

  private handleJoinQueue(socket: Socket, data: { userId: string; username: string }): void {
    const { userId, username } = data;

    // Check if player is already in a match
    if (this.playerToMatch.has(userId)) {
      socket.emit('error', { message: 'Already in a match' });
      return;
    }

    // Check if player is already in queue
    if (this.playerQueue.has(userId)) {
      socket.emit('error', { message: 'Already in queue' });
      return;
    }

    const player: Player = {
      id: userId,
      socketId: socket.id,
      username,
      taps: 0,
      isReady: false,
      lastTapTimestamp: 0,
      validatedTaps: 0,
    };

    this.queue.players.set(userId, player);
    this.playerQueue.set(userId, 'main');
    socket.join('queue');

    console.log(`${username} joined queue. Queue size: ${this.queue.players.size}`);
    socket.emit('queue_joined', { position: this.queue.players.size });

    // Attempt to create a match if enough players
    if (this.queue.players.size >= this.MATCH_SIZE) {
      this.createMatch();
    }
  }

  private handleLeaveQueue(socket: Socket, data: { userId: string }): void {
    const { userId } = data;

    if (!this.playerQueue.has(userId)) {
      socket.emit('error', { message: 'Not in queue' });
      return;
    }

    this.queue.players.delete(userId);
    this.playerQueue.delete(userId);
    socket.leave('queue');

    console.log(`${userId} left queue. Queue size: ${this.queue.players.size}`);
    socket.emit('queue_left');
  }

  private createMatch(): void {
    if (this.queue.players.size < this.MATCH_SIZE) {
      return;
    }

    const matchId = uuidv4();
    const players = new Map<string, Player>();
    const queueArray = Array.from(this.queue.players.values());

    // Take first MATCH_SIZE players from queue
    for (let i = 0; i < this.MATCH_SIZE; i++) {
      const player = queueArray[i];
      players.set(player.id, player);
      this.queue.players.delete(player.id);
      this.playerQueue.delete(player.id);
      this.playerToMatch.set(player.id, matchId);
    }

    const match: GameMatch = {
      id: matchId,
      players,
      status: 'waiting',
      startTime: null,
      endTime: null,
      duration: this.MATCH_DURATION,
      winner: null,
    };

    this.matches.set(matchId, match);

    // Notify players
    players.forEach((player) => {
      this.io.to(player.socketId).emit('match_found', {
        matchId,
        players: Array.from(players.values()).map((p) => ({
          id: p.id,
          username: p.username,
        })),
      });
    });

    console.log(`Match created: ${matchId} with ${players.size} players`);

    // Start match after brief delay
    setTimeout(() => this.startMatch(matchId), 2000);
  }

  private startMatch(matchId: string): void {
    const match = this.matches.get(matchId);
    if (!match) return;

    match.status = 'active';
    match.startTime = Date.now();

    match.players.forEach((player) => {
      this.io.to(player.socketId).emit('match_started', {
        matchId,
        duration: match.duration,
        startTime: match.startTime,
      });
    });

    console.log(`Match started: ${matchId}`);

    // End match after duration
    setTimeout(() => this.endMatch(matchId), match.duration);
  }

  private handlePlayerReady(socket: Socket, data: { userId: string; matchId: string }): void {
    const { userId, matchId } = data;
    const match = this.matches.get(matchId);

    if (!match) {
      socket.emit('error', { message: 'Match not found' });
      return;
    }

    const player = match.players.get(userId);
    if (!player) {
      socket.emit('error', { message: 'Player not in match' });
      return;
    }

    player.isReady = true;

    const allReady = Array.from(match.players.values()).every((p) => p.isReady);
    if (allReady && match.status === 'waiting') {
      this.startMatch(matchId);
    }
  }

  private handleTap(socket: Socket, data: { userId: string; matchId: string; timestamp: number }): void {
    const { userId, matchId, timestamp } = data;
    const match = this.matches.get(matchId);

    if (!match) {
      socket.emit('error', { message: 'Match not found' });
      return;
    }

    if (match.status !== 'active') {
      socket.emit('error', { message: 'Match not active' });
      return;
    }

    const player = match.players.get(userId);
    if (!player) {
      socket.emit('error', { message: 'Player not in match' });
      return;
    }

    // Authoritative server validation
    if (!this.validateTap(player, timestamp)) {
      console.warn(`Invalid tap from ${userId} in match ${matchId}`);
      socket.emit('error', { message: 'Invalid tap detected' });
      return;
    }

    player.validatedTaps++;
    player.taps++;

    // Broadcast tap to all players in match
    this.io.to(matchId).emit('player_tapped', {
      playerId: userId,
      username: player.username,
      tapCount: player.validatedTaps,
    });

    socket.emit('tap_confirmed', { tapCount: player.validatedTaps });
  }

  private validateTap(player: Player, timestamp: number): boolean {
    const currentTime = Date.now();

    // Validate timestamp is within acceptable range
    const timeDifference = Math.abs(currentTime - timestamp);
    if (timeDifference > this.TAP_VALIDATION_WINDOW) {
      return false;
    }

    // Check tap rate (anti-cheat)
    const timeSinceLastTap = currentTime - player.lastTapTimestamp;
    if (timeSinceLastTap < 1000 / this.MAX_TAPS_PER_SECOND) {
      return false;
    }

    player.lastTapTimestamp = currentTime;
    return true;
  }

  private endMatch(matchId: string): void {
    const match = this.matches.get(matchId);
    if (!match) return;

    match.status = 'finished';
    match.endTime = Date.now();

    // Determine winner
    let maxTaps = -1;
    let winner: Player | null = null;

    match.players.forEach((player) => {
      if (player.validatedTaps > maxTaps) {
        maxTaps = player.validatedTaps;
        winner = player;
      }
    });

    if (winner) {
      match.winner = winner.id;
    }

    // Notify players of results
    const results = Array.from(match.players.values())
      .map((p) => ({
        id: p.id,
        username: p.username,
        taps: p.validatedTaps,
        isWinner: p.id === match.winner,
      }))
      .sort((a, b) => b.taps - a.taps);

    match.players.forEach((player) => {
      this.io.to(player.socketId).emit('match_ended', {
        matchId,
        results,
        winnerId: match.winner,
      });
    });

    console.log(`Match ended: ${matchId}, Winner: ${match.winner}`);

    // Clean up
    setTimeout(() => {
      this.matches.delete(matchId);
      match.players.forEach((player) => {
        this.playerToMatch.delete(player.id);
      });
    }, 5000);
  }

  private handleDisconnect(socket: Socket): void {
    console.log(`Player disconnected: ${socket.id}`);

    // Remove from queue
    Array.from(this.queue.players.entries()).forEach(([playerId, player]) => {
      if (player.socketId === socket.id) {
        this.queue.players.delete(playerId);
        this.playerQueue.delete(playerId);
      }
    });

    // Remove from active match
    this.matches.forEach((match, matchId) => {
      Array.from(match.players.entries()).forEach(([playerId, player]) => {
        if (player.socketId === socket.id) {
          match.players.delete(playerId);
          this.playerToMatch.delete(playerId);

          // Notify remaining players
          match.players.forEach((p) => {
            this.io.to(p.socketId).emit('player_disconnected', { playerId });
          });

          // End match if too many disconnections
          if (match.players.size === 0) {
            this.endMatch(matchId);
          }
        }
      });
    });
  }

  // Utility methods
  public getMatchStatus(matchId: string): GameMatch | undefined {
    return this.matches.get(matchId);
  }

  public getQueueSize(): number {
    return this.queue.players.size;
  }

  public getActiveMatches(): number {
    return this.matches.size;
  }

  public getPlayerStats(userId: string): { inQueue: boolean; inMatch: boolean; matchId?: string } {
    return {
      inQueue: this.playerQueue.has(userId),
      inMatch: this.playerToMatch.has(userId),
      matchId: this.playerToMatch.get(userId),
    };
  }
}

export default TapRaceMatchmaker;
