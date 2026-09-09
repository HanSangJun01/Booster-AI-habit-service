import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/app_user.dart';
import '../../services/user_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';

/// 코인 내역 — `GET /api/users/me/coins` (페이징).
///
/// 서버가 size를 1~100으로 클램프하고 총 개수(`totalCount`)를 함께 준다.
class CoinHistoryScreen extends StatefulWidget {
  const CoinHistoryScreen({super.key});
  @override
  State<CoinHistoryScreen> createState() => _CoinHistoryScreenState();
}

class _CoinHistoryScreenState extends State<CoinHistoryScreen> {
  static const _pageSize = 20;

  final _transactions = <CoinTransaction>[];
  final _scrollController = ScrollController();
  int _page = 0;
  int _totalCount = 0;
  bool _loading = true;
  bool _loadingMore = false;

  bool get _hasMore => _transactions.length < _totalCount;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) _loadMore();
  }

  Future<void> _loadFirst() async {
    setState(() => _loading = true);
    try {
      final history = await UserService.fetchCoinHistory(page: 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _transactions
          ..clear()
          ..addAll(history.transactions);
        _totalCount = history.totalCount;
        _page = 0;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final history = await UserService.fetchCoinHistory(page: next, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _transactions.addAll(history.transactions);
        _totalCount = history.totalCount;
        _page = next;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '코인 내역', trailing: CoinPill()),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BC.oMain));
    }
    if (_transactions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
        children: const [
          Icon(Icons.receipt_long_rounded, size: 36, color: BC.ink3),
          SizedBox(height: 10),
          Center(
            child: Text('아직 코인 내역이 없어요',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BC.ink2)),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirst,
      color: BC.oMain,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: _transactions.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index >= _transactions.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: BC.oMain, strokeWidth: 2.4),
                ),
              ),
            );
          }
          return _tile(_transactions[index]);
        },
      ),
    );
  }

  Widget _tile(CoinTransaction tx) {
    final gain = tx.isGain;
    final color = gain ? BC.green : BC.oMain;
    final created = tx.createdAt;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: gain ? BC.greenSoft : BC.oSoft,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(gain ? Icons.add_rounded : Icons.remove_rounded,
                size: 20, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (created != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${created.year}.${created.month.toString().padLeft(2, '0')}.'
                      '${created.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12, color: BC.ink3),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${gain ? '+' : ''}${CoinPill.format(tx.amount)}',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: color)),
              Text('잔액 ${CoinPill.format(tx.balanceAfter)}',
                  style: const TextStyle(fontSize: 11.5, color: BC.ink3)),
            ],
          ),
        ],
      ),
    );
  }
}
