// lib/main.dart
//
// 【処理概要】
// カスタム状態管理ライブラリのデモアプリ。
// カウンターアプリをベースに、高度な機能を実装する。
//
// 【主な機能】
// - カウンター操作（増減、リセット）
// - 非同期データフェッチ
// - Undo/Redo機能
// - アクション履歴の表示
// - パフォーマンス最適化
//
// 【実装内容】
// 1. AppStateの定義
// 2. Actionの定義
// 3. Reducerの実装
// 4. UIの構築

import 'package:flutter/material.dart';
import 'state_manager.dart';
import 'reactive_builder.dart';
import 'middleware.dart';

void main() {
  runApp(const MyApp());
}

// ===== アプリケーション状態 =====

/// アプリケーションの状態を表すクラス
class AppState {
  final int counter;
  final bool isLoading;
  final String? errorMessage;
  final List<String> messages;
  
  const AppState({
    required this.counter,
    this.isLoading = false,
    this.errorMessage,
    this.messages = const [],
  });
  
  /// コピーメソッド（イミュータブルな更新）
  AppState copyWith({
    int? counter,
    bool? isLoading,
    String? errorMessage,
    List<String>? messages,
  }) {
    return AppState(
      counter: counter ?? this.counter,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      messages: messages ?? this.messages,
    );
  }
  
  @override
  String toString() => 'AppState(counter: $counter, loading: $isLoading)';
  
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppState &&
            counter == other.counter &&
            isLoading == other.isLoading &&
            errorMessage == other.errorMessage;
  }
  
  @override
  int get hashCode => Object.hash(counter, isLoading, errorMessage);
}

// ===== アクション定義 =====

/// カウンターを増加させるアクション
class IncrementAction extends Action {
  final int amount;
  IncrementAction([this.amount = 1]);
  
  @override
  String toString() => 'IncrementAction($amount)';
}

/// カウンターを減少させるアクション
class DecrementAction extends Action {
  final int amount;
  DecrementAction([this.amount = 1]);
  
  @override
  String toString() => 'DecrementAction($amount)';
}

/// カウンターをリセットするアクション
class ResetAction extends Action {
  @override
  String toString() => 'ResetAction';
}

/// 非同期データフェッチ開始アクション
class FetchDataStartAction extends Action {}

/// 非同期データフェッチ成功アクション
class FetchDataSuccessAction extends Action {
  final String data;
  FetchDataSuccessAction(this.data);
}

/// 非同期データフェッチ失敗アクション
class FetchDataErrorAction extends Action {
  final String error;
  FetchDataErrorAction(this.error);
}

/// メッセージ追加アクション
class AddMessageAction extends Action {
  final String message;
  AddMessageAction(this.message);
}

// ===== リデューサー =====

/// アプリケーションのリデューサー
/// 
/// 純粋関数として実装し、状態を変更せず新しい状態を返す
AppState appReducer(AppState state, Action action) {
  if (action is IncrementAction) {
    return state.copyWith(counter: state.counter + action.amount);
  }
  
  if (action is DecrementAction) {
    return state.copyWith(counter: state.counter - action.amount);
  }
  
  if (action is ResetAction) {
    return state.copyWith(counter: 0);
  }
  
  if (action is FetchDataStartAction) {
    return state.copyWith(
      isLoading: true,
      errorMessage: null,
    );
  }
  
  if (action is FetchDataSuccessAction) {
    return state.copyWith(
      isLoading: false,
      messages: [...state.messages, action.data],
    );
  }
  
  if (action is FetchDataErrorAction) {
    return state.copyWith(
      isLoading: false,
      errorMessage: action.error,
    );
  }
  
  if (action is AddMessageAction) {
    return state.copyWith(
      messages: [...state.messages, action.message],
    );
  }
  
  return state;
}

// ===== 非同期アクション =====

/// データをフェッチする非同期アクション
AsyncAction fetchDataAction() {
  return AsyncAction((store) async {
    // フェッチ開始
    store.dispatch(FetchDataStartAction());
    
    try {
      // 擬似的なAPI呼び出し（2秒待機）
      await Future.delayed(const Duration(seconds: 2));
      
      // ランダムでエラーをシミュレート
      if (DateTime.now().second % 3 == 0) {
        throw Exception('Network error');
      }
      
      // 成功
      final data = 'Data fetched at ${DateTime.now().toIso8601String()}';
      store.dispatch(FetchDataSuccessAction(data));
      
    } catch (e) {
      // エラー
      store.dispatch(FetchDataErrorAction(e.toString()));
    }
  });
}

// ===== アプリケーション =====

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Storeの初期化
    final store = Store<AppState>(
      initialState: const AppState(counter: 0),
      reducer: appReducer,
      enableHistory: true, // タイムトラベル有効化
      maxHistorySize: 50,
      middleware: [
        createAsyncMiddleware<AppState>(),
        createTimestampedLoggingMiddleware<AppState>(),
        createPerformanceMiddleware<AppState>(),
        createErrorHandlingMiddleware<AppState>(),
        ThrottleMiddleware<AppState>(
          duration: const Duration(milliseconds: 500),
        ).create(),
      ],
    );

    return StoreProvider<AppState>(
      store: store,
      child: MaterialApp(
        title: 'Custom State Manager Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}

// ===== ホーム画面 =====

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('状態管理デモ'),
        actions: [
          // Undo/Redoボタン
          StoreBuilder<AppState>(
            builder: (context, state) {
              final store = context.store<AppState>();
              
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: store.canUndo ? () => store.undo() : null,
                    tooltip: 'Undo',
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo),
                    onPressed: store.canRedo ? () => store.redo() : null,
                    tooltip: 'Redo',
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // カウンター表示
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'カウンター:',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 16),
                  
                  // StoreSelector使用（counterのみ監視）
                  StoreSelector<AppState, int>(
                    selector: (state) => state.counter,
                    builder: (context, counter) {
                      return Text(
                        '$counter',
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // ボタン群
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => context.dispatch<AppState>(
                          DecrementAction(),
                        ),
                        icon: const Icon(Icons.remove),
                        label: const Text('-1'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => context.dispatch<AppState>(
                          IncrementAction(),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('+1'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => context.dispatch<AppState>(
                          IncrementAction(10),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('+10'),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  ElevatedButton.icon(
                    onPressed: () => context.dispatch<AppState>(
                      ResetAction(),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('リセット'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // 非同期データフェッチ
                  StoreBuilder<AppState>(
                    builder: (context, state) {
                      return Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: state.isLoading
                                ? null
                                : () => context.store<AppState>()
                                    .dispatch(fetchDataAction()),
                            icon: state.isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download),
                            label: Text(
                              state.isLoading
                                  ? 'Loading...'
                                  : 'データ取得',
                            ),
                          ),
                          
                          if (state.errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '❌ ${state.errorMessage}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // メッセージリスト
          const Divider(),
          const MessageList(),
          
          // アクション履歴
          const Divider(),
          const ActionHistoryList(),
        ],
      ),
    );
  }
}

// ===== メッセージリスト =====

class MessageList extends StatelessWidget {
  const MessageList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StoreSelector<AppState, List<String>>(
      selector: (state) => state.messages,
      builder: (context, messages) {
        if (messages.isEmpty) {
          return const SizedBox.shrink();
        }
        
        return Container(
          height: 150,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '📨 メッセージ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return Text('• ${messages[index]}');
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===== アクション履歴 =====

class ActionHistoryList extends StatelessWidget {
  const ActionHistoryList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final store = context.store<AppState>();
    final actions = store.actionHistory;
    
    return Container(
      height: 150,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '📜 アクション履歴:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text('${actions.length}件'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: actions.length,
              itemBuilder: (context, index) {
                final action = actions[actions.length - 1 - index];
                return Text(
                  '${index + 1}. $action',
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
