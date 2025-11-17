// lib/state_manager.dart
//
// 【処理概要】
// カスタム状態管理ライブラリのコア実装。
// Reduxライクなアーキテクチャで、状態の一元管理と
// タイムトラベルデバッグを提供する。
//
// 【主な機能】
// - イミュータブルな状態管理
// - アクションベースの状態更新
// - リデューサーパターン
// - ミドルウェアチェーン
// - 状態履歴の管理（Undo/Redo）
// - Streamベースの変更通知
//
// 【実装内容】
// 1. Storeクラス - 状態の保持と更新
// 2. Action - 状態変更の意図を表現
// 3. Reducer - 純粋関数での状態変化
// 4. Middleware - 副作用の処理
// 5. StateHistory - タイムトラベル機能

import 'dart:async';
import 'dart:collection';

/// アクションの基底クラス
/// 全てのアクションはこれを継承する
abstract class Action {
  final DateTime timestamp = DateTime.now();
  
  @override
  String toString() => runtimeType.toString();
}

/// リデューサー関数の型定義
/// 現在の状態とアクションを受け取り、新しい状態を返す（純粋関数）
typedef Reducer<T> = T Function(T state, Action action);

/// ミドルウェア関数の型定義
/// Storeとアクション、next関数を受け取る
typedef Middleware<T> = void Function(
  Store<T> store,
  Action action,
  NextDispatcher next,
);

/// 次のミドルウェアを呼び出す関数
typedef NextDispatcher = void Function(Action action);

/// 状態管理の中核となるStoreクラス
/// 
/// Redux風の単一ストア実装で、以下の責務を持つ：
/// - 状態の保持
/// - アクションのディスパッチ
/// - リデューサーによる状態更新
/// - ミドルウェアの実行
/// - 変更通知（Stream）
/// - 状態履歴の管理
class Store<T> {
  T _state;
  final Reducer<T> _reducer;
  final List<Middleware<T>> _middleware;
  
  // 状態変更を通知するStreamController
  final _stateController = StreamController<T>.broadcast();
  
  // 状態履歴（タイムトラベル用）
  final StateHistory<T> _history;
  final bool _enableHistory;
  
  // アクション履歴（デバッグ用）
  final List<Action> _actionHistory = [];
  final int _maxActionHistory;
  
  /// コンストラクタ
  /// 
  /// [initialState] - 初期状態
  /// [reducer] - リデューサー関数
  /// [middleware] - ミドルウェアリスト
  /// [enableHistory] - タイムトラベル機能の有効化
  /// [maxHistorySize] - 履歴の最大保持数
  Store({
    required T initialState,
    required Reducer<T> reducer,
    List<Middleware<T>>? middleware,
    bool enableHistory = false,
    int maxHistorySize = 50,
    int maxActionHistory = 100,
  })  : _state = initialState,
        _reducer = reducer,
        _middleware = middleware ?? [],
        _enableHistory = enableHistory,
        _history = StateHistory<T>(maxSize: maxHistorySize),
        _maxActionHistory = maxActionHistory {
    
    // 初期状態を履歴に追加
    if (_enableHistory) {
      _history.push(initialState);
    }
  }
  
  /// 現在の状態を取得
  T get state => _state;
  
  /// 状態変更のStream
  Stream<T> get stream => _stateController.stream;
  
  /// アクション履歴を取得
  List<Action> get actionHistory => UnmodifiableListView(_actionHistory);
  
  /// 状態履歴のサイズを取得
  int get historySize => _history.size;
  
  /// Undo可能かチェック
  bool get canUndo => _history.canUndo;
  
  /// Redo可能かチェック
  bool get canRedo => _history.canRedo;
  
  /// アクションをディスパッチ
  /// 
  /// ミドルウェアチェーンを通過後、リデューサーで状態を更新する
  /// 
  /// [action] - ディスパッチするアクション
  void dispatch(Action action) {
    // アクション履歴に追加
    _addActionToHistory(action);
    
    // ミドルウェアチェーンを構築
    void Function(Action) chain = _createMiddlewareChain();
    
    // ミドルウェアチェーンを実行
    chain(action);
  }
  
  /// ミドルウェアチェーンを作成
  void Function(Action) _createMiddlewareChain() {
    // 最終的なディスパッチ処理（リデューサー実行）
    NextDispatcher finalDispatcher = (Action action) {
      _applyReducer(action);
    };
    
    // ミドルウェアを逆順で畳み込んでチェーンを作成
    NextDispatcher chain = finalDispatcher;
    
    for (var i = _middleware.length - 1; i >= 0; i--) {
      final middleware = _middleware[i];
      final next = chain;
      
      chain = (Action action) {
        middleware(this, action, next);
      };
    }
    
    return chain;
  }
  
  /// リデューサーを適用して状態を更新
  void _applyReducer(Action action) {
    final newState = _reducer(_state, action);
    
    if (newState != _state) {
      _state = newState;
      
      // 履歴に追加
      if (_enableHistory) {
        _history.push(newState);
      }
      
      // 変更を通知
      _stateController.add(_state);
    }
  }
  
  /// アクション履歴に追加
  void _addActionToHistory(Action action) {
    _actionHistory.add(action);
    
    // 最大数を超えたら古いものから削除
    if (_actionHistory.length > _maxActionHistory) {
      _actionHistory.removeAt(0);
    }
  }
  
  /// Undo（状態を1つ前に戻す）
  void undo() {
    if (!_enableHistory) {
      throw StateError('History is not enabled');
    }
    
    final previousState = _history.undo();
    if (previousState != null) {
      _state = previousState;
      _stateController.add(_state);
    }
  }
  
  /// Redo（状態を1つ進める）
  void redo() {
    if (!_enableHistory) {
      throw StateError('History is not enabled');
    }
    
    final nextState = _history.redo();
    if (nextState != null) {
      _state = nextState;
      _stateController.add(_state);
    }
  }
  
  /// アクション履歴をクリア
  void clearActionHistory() {
    _actionHistory.clear();
  }
  
  /// Storeをクローズ（リソース解放）
  void dispose() {
    _stateController.close();
  }
}

/// 状態履歴を管理するクラス
/// 
/// タイムトラベルデバッグのために、
/// 状態の履歴をスタック構造で保持する
class StateHistory<T> {
  final int maxSize;
  final List<T> _history = [];
  int _currentIndex = -1;
  
  StateHistory({required this.maxSize});
  
  /// 履歴に状態を追加
  void push(T state) {
    // 現在位置より後ろの履歴を削除（新しい分岐）
    if (_currentIndex < _history.length - 1) {
      _history.removeRange(_currentIndex + 1, _history.length);
    }
    
    // 新しい状態を追加
    _history.add(state);
    _currentIndex++;
    
    // 最大サイズを超えたら古いものから削除
    if (_history.length > maxSize) {
      _history.removeAt(0);
      _currentIndex--;
    }
  }
  
  /// 1つ前の状態に戻る
  T? undo() {
    if (!canUndo) return null;
    
    _currentIndex--;
    return _history[_currentIndex];
  }
  
  /// 1つ先の状態に進む
  T? redo() {
    if (!canRedo) return null;
    
    _currentIndex++;
    return _history[_currentIndex];
  }
  
  /// Undo可能かチェック
  bool get canUndo => _currentIndex > 0;
  
  /// Redo可能かチェック
  bool get canRedo => _currentIndex < _history.length - 1;
  
  /// 履歴のサイズ
  int get size => _history.length;
  
  /// 現在のインデックス
  int get currentIndex => _currentIndex;
}

/// 非同期アクションのサポート
/// 
/// 非同期処理を含むアクションをディスパッチするための
/// Thunkパターン実装
class AsyncAction extends Action {
  final Future<void> Function(Store store) execute;
  
  AsyncAction(this.execute);
}

/// 非同期アクションを処理するミドルウェア
Middleware<T> createAsyncMiddleware<T>() {
  return (store, action, next) {
    if (action is AsyncAction) {
      // 非同期処理を実行
      action.execute(store).catchError((error) {
        print('非同期アクションでエラー: $error');
      });
    } else {
      next(action);
    }
  };
}

/// ロギングミドルウェア
/// 
/// 全てのアクションとその前後の状態をログ出力する
Middleware<T> createLoggingMiddleware<T>() {
  return (store, action, next) {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🎬 Action: $action');
    print('📦 Previous State: ${store.state}');
    
    final stopwatch = Stopwatch()..start();
    next(action);
    stopwatch.stop();
    
    print('📦 New State: ${store.state}');
    print('⏱️  Duration: ${stopwatch.elapsedMicroseconds}μs');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  };
}
