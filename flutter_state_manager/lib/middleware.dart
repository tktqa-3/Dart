// lib/middleware.dart
//
// 【処理概要】
// 状態管理のミドルウェア実装。
// アクションの前後に副作用を挿入できる。
//
// 【主な機能】
// - ロギングミドルウェア（デバッグ用）
// - パフォーマンス計測ミドルウェア
// - エラーハンドリングミドルウェア
// - 永続化ミドルウェア（ローカルストレージ）
// - スロットリング/デバウンスミドルウェア
//
// 【実装内容】
// 1. 各種ミドルウェアの実装
// 2. チェーン可能な設計
// 3. 非同期処理対応
// 4. カスタマイズ可能なオプション

import 'dart:async';
import 'state_manager.dart';

/// パフォーマンス計測ミドルウェア
/// 
/// 各アクションの実行時間を測定し、
/// 遅いアクションを警告する
Middleware<T> createPerformanceMiddleware<T>({
  int warningThresholdMs = 16, // 16ms以上で警告（60fps基準）
}) {
  return (store, action, next) {
    final stopwatch = Stopwatch()..start();
    
    next(action);
    
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMilliseconds;
    
    if (elapsedMs > warningThresholdMs) {
      print('⚠️  Slow action detected: $action took ${elapsedMs}ms');
    }
  };
}

/// エラーハンドリングミドルウェア
/// 
/// リデューサーでエラーが発生した場合に
/// キャッチして適切に処理する
Middleware<T> createErrorHandlingMiddleware<T>({
  void Function(Object error, StackTrace stack, Action action)? onError,
}) {
  return (store, action, next) {
    try {
      next(action);
    } catch (error, stack) {
      print('❌ Error in reducer for action $action: $error');
      print(stack);
      
      onError?.call(error, stack, action);
      
      // エラーを再スローしない（アプリをクラッシュさせない）
    }
  };
}

/// デバウンスミドルウェア
/// 
/// 連続したアクションを一定時間遅延させ、
/// 最後のアクションのみ実行する
class DebounceMiddleware<T> {
  final Duration duration;
  final Map<Type, Timer> _timers = {};
  
  DebounceMiddleware({
    this.duration = const Duration(milliseconds: 300),
  });
  
  Middleware<T> create() {
    return (store, action, next) {
      final actionType = action.runtimeType;
      
      // 既存のタイマーをキャンセル
      _timers[actionType]?.cancel();
      
      // 新しいタイマーを設定
      _timers[actionType] = Timer(duration, () {
        next(action);
        _timers.remove(actionType);
      });
    };
  }
}

/// スロットリングミドルウェア
/// 
/// 一定期間内に同じアクションが複数回呼ばれても、
/// 最初の1回だけ実行する
class ThrottleMiddleware<T> {
  final Duration duration;
  final Map<Type, DateTime> _lastExecuted = {};
  
  ThrottleMiddleware({
    this.duration = const Duration(milliseconds: 1000),
  });
  
  Middleware<T> create() {
    return (store, action, next) {
      final actionType = action.runtimeType;
      final now = DateTime.now();
      final lastTime = _lastExecuted[actionType];
      
      if (lastTime == null || now.difference(lastTime) > duration) {
        _lastExecuted[actionType] = now;
        next(action);
      } else {
        print('🚫 Action throttled: $action');
      }
    };
  }
}

/// アクションフィルターミドルウェア
/// 
/// 特定の条件でアクションをブロックする
Middleware<T> createFilterMiddleware<T>({
  required bool Function(Action action) shouldProcess,
  void Function(Action action)? onFiltered,
}) {
  return (store, action, next) {
    if (shouldProcess(action)) {
      next(action);
    } else {
      print('🚫 Action filtered: $action');
      onFiltered?.call(action);
    }
  };
}

/// アクション変換ミドルウェア
/// 
/// アクションを別のアクションに変換する
/// （例: ユーザーアクション → 分析イベント）
Middleware<T> createTransformMiddleware<T>({
  required Action? Function(Action action) transform,
}) {
  return (store, action, next) {
    final transformedAction = transform(action);
    
    if (transformedAction != null) {
      next(transformedAction);
    } else {
      next(action);
    }
  };
}

/// 複数アクションディスパッチミドルウェア
/// 
/// 1つのアクションが複数のアクションを生成できる
class BatchAction extends Action {
  final List<Action> actions;
  
  BatchAction(this.actions);
  
  @override
  String toString() => 'BatchAction(${actions.length} actions)';
}

Middleware<T> createBatchMiddleware<T>() {
  return (store, action, next) {
    if (action is BatchAction) {
      // バッチ内の各アクションを順次ディスパッチ
      for (final batchedAction in action.actions) {
        store.dispatch(batchedAction);
      }
    } else {
      next(action);
    }
  };
}

/// 条件付きディスパッチミドルウェア
/// 
/// 現在の状態に基づいてアクションを実行するか判定
Middleware<T> createConditionalMiddleware<T>({
  required bool Function(T state, Action action) condition,
  void Function(Action action)? onRejected,
}) {
  return (store, action, next) {
    if (condition(store.state, action)) {
      next(action);
    } else {
      print('🚫 Action rejected by condition: $action');
      onRejected?.call(action);
    }
  };
}

/// デバッグモード限定ミドルウェア
/// 
/// リリースビルドでは実行されない
Middleware<T> createDebugOnlyMiddleware<T>(
  Middleware<T> middleware,
) {
  return (store, action, next) {
    assert(() {
      middleware(store, action, next);
      return true;
    }());
    
    // リリースモードでは素通り
    if (!_isDebugMode()) {
      next(action);
    }
  };
}

bool _isDebugMode() {
  bool debugMode = false;
  assert(() {
    debugMode = true;
    return true;
  }());
  return debugMode;
}

/// タイムスタンプ付きロギングミドルウェア
Middleware<T> createTimestampedLoggingMiddleware<T>({
  bool logState = true,
  bool logPerformance = true,
}) {
  return (store, action, next) {
    final timestamp = DateTime.now().toIso8601String();
    final stopwatch = Stopwatch()..start();
    
    print('');
    print('┌─────────────────────────────────────────');
    print('│ ⏰ $timestamp');
    print('│ 🎬 Action: $action');
    
    if (logState) {
      print('│ 📦 State Before: ${store.state}');
    }
    
    next(action);
    
    stopwatch.stop();
    
    if (logState) {
      print('│ 📦 State After: ${store.state}');
    }
    
    if (logPerformance) {
      print('│ ⏱️  Duration: ${stopwatch.elapsedMicroseconds}μs');
    }
    
    print('└─────────────────────────────────────────');
    print('');
  };
}
