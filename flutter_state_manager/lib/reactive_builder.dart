// lib/reactive_builder.dart
//
// 【処理概要】
// リアクティブUIを構築するためのWidgetクラス群。
// Storeの状態変化を監視し、効率的にUIを再描画する。
//
// 【主な機能】
// - StoreBuilder - 状態変化でUI再描画
// - StoreSelector - 部分的な状態変化のみ監視（最適化）
// - StoreConnector - 複雑なマッピング処理
// - StoreProvider - Storeの提供（Context経由）
//
// 【実装内容】
// 1. InheritedWidgetでStoreを子孫に提供
// 2. StreamBuilderベースのリアクティブWidget
// 3. Selectorによる再描画の最適化
// 4. ライフサイクル管理（dispose）

import 'package:flutter/widgets.dart';
import 'state_manager.dart';

/// Storeを子孫Widgetに提供するInheritedWidget
/// 
/// Contextを通じてStoreにアクセスできるようにする
class StoreProvider<T> extends InheritedWidget {
  final Store<T> store;

  const StoreProvider({
    Key? key,
    required this.store,
    required Widget child,
  }) : super(key: key, child: child);

  /// Contextから最も近いStoreProviderを取得
  static Store<T> of<T>(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<StoreProvider<T>>();
    
    if (provider == null) {
      throw StateError(
        'StoreProvider<$T> not found in widget tree. '
        'Make sure to wrap your app with StoreProvider.',
      );
    }
    
    return provider.store;
  }

  @override
  bool updateShouldNotify(StoreProvider<T> oldWidget) {
    return store != oldWidget.store;
  }
}

/// Storeの状態変化を監視してUIを再構築するWidget
/// 
/// StreamBuilderをラップして、Storeの状態変化に対応する
class StoreBuilder<T> extends StatelessWidget {
  final Widget Function(BuildContext context, T state) builder;
  final Store<T>? store;

  const StoreBuilder({
    Key? key,
    required this.builder,
    this.store,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final storeInstance = store ?? StoreProvider.of<T>(context);

    return StreamBuilder<T>(
      stream: storeInstance.stream,
      initialData: storeInstance.state,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        return builder(context, snapshot.data as T);
      },
    );
  }
}

/// 状態の一部だけを監視するWidget（パフォーマンス最適化）
/// 
/// Selectorで選択した値が変更された場合のみ再描画される
/// これにより、不要な再描画を防ぐ
class StoreSelector<T, S> extends StatefulWidget {
  final S Function(T state) selector;
  final Widget Function(BuildContext context, S selected) builder;
  final Store<T>? store;
  final bool Function(S prev, S next)? shouldRebuild;

  const StoreSelector({
    Key? key,
    required this.selector,
    required this.builder,
    this.store,
    this.shouldRebuild,
  }) : super(key: key);

  @override
  State<StoreSelector<T, S>> createState() => _StoreSelectorState<T, S>();
}

class _StoreSelectorState<T, S> extends State<StoreSelector<T, S>> {
  late Store<T> _store;
  late S _selectedState;
  late StreamSubscription<T> _subscription;

  @override
  void initState() {
    super.initState();
    _initializeStore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeStore();
  }

  void _initializeStore() {
    _store = widget.store ?? StoreProvider.of<T>(context);
    _selectedState = widget.selector(_store.state);

    _subscription = _store.stream.listen((state) {
      final newSelected = widget.selector(state);
      
      // shouldRebuildが指定されていればそれを使用、なければ等価比較
      final shouldUpdate = widget.shouldRebuild?.call(_selectedState, newSelected) 
        ?? (_selectedState != newSelected);

      if (shouldUpdate) {
        setState(() {
          _selectedState = newSelected;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _selectedState);
  }
}

/// より柔軟な状態変換とUI構築を行うConnector
/// 
/// 状態から任意の型へ変換し、さらにディスパッチ関数も提供する
class StoreConnector<T, ViewModel> extends StatelessWidget {
  final ViewModel Function(T state) converter;
  final Widget Function(BuildContext context, ViewModel viewModel) builder;
  final void Function(Store<T> store)? onInit;
  final void Function(Store<T> store)? onDispose;
  final bool Function(T prev, T next)? distinct;
  final Store<T>? store;

  const StoreConnector({
    Key? key,
    required this.converter,
    required this.builder,
    this.onInit,
    this.onDispose,
    this.distinct,
    this.store,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _StoreStreamListener<T, ViewModel>(
      store: store,
      converter: converter,
      builder: builder,
      onInit: onInit,
      onDispose: onDispose,
      distinct: distinct,
    );
  }
}

/// StoreConnectorの内部実装
class _StoreStreamListener<T, ViewModel> extends StatefulWidget {
  final ViewModel Function(T state) converter;
  final Widget Function(BuildContext context, ViewModel viewModel) builder;
  final void Function(Store<T> store)? onInit;
  final void Function(Store<T> store)? onDispose;
  final bool Function(T prev, T next)? distinct;
  final Store<T>? store;

  const _StoreStreamListener({
    required this.converter,
    required this.builder,
    this.onInit,
    this.onDispose,
    this.distinct,
    this.store,
  });

  @override
  State<_StoreStreamListener<T, ViewModel>> createState() =>
      _StoreStreamListenerState<T, ViewModel>();
}

class _StoreStreamListenerState<T, ViewModel>
    extends State<_StoreStreamListener<T, ViewModel>> {
  late Store<T> _store;
  late StreamSubscription<T> _subscription;
  late ViewModel _latestViewModel;

  @override
  void initState() {
    super.initState();
    _initStore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initStore();
  }

  void _initStore() {
    _store = widget.store ?? StoreProvider.of<T>(context);
    _latestViewModel = widget.converter(_store.state);

    // onInitコールバック
    widget.onInit?.call(_store);

    _subscription = _store.stream.listen((state) {
      final newViewModel = widget.converter(state);

      setState(() {
        _latestViewModel = newViewModel;
      });
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    widget.onDispose?.call(_store);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _latestViewModel);
  }
}

/// アクションディスパッチ用のヘルパー関数
extension StoreContextExtension on BuildContext {
  /// Contextから直接Storeを取得
  Store<T> store<T>() => StoreProvider.of<T>(this);
  
  /// Contextから直接アクションをディスパッチ
  void dispatch<T>(Action action) {
    StoreProvider.of<T>(this).dispatch(action);
  }
}
