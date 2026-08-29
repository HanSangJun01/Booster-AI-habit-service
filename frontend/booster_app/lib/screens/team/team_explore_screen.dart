import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/challenge.dart';
import '../../models/challenge_category.dart';
import '../../services/challenge_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import 'team_detail_screen.dart';

/// 챌린지 탐색 — `GET /api/challenges` (공개 챌린지 검색, 페이징).
///
/// 비공개 챌린지는 목록에 안 나오고, 초대 코드로만 찾을 수 있다
/// (`GET /api/challenges/invite/{code}`).
class TeamExploreScreen extends StatefulWidget {
  const TeamExploreScreen({super.key});

  @override
  State<TeamExploreScreen> createState() => _TeamExploreScreenState();
}

class _TeamExploreScreenState extends State<TeamExploreScreen> {
  static const _pageSize = 20;

  /// 필터 칩. 첫 칸('전체')은 카테고리를 안 보내는 자리라 null이다.
  ///
  /// 독서가 빠진 건 공부와 **전송값이 같아서**다(둘 다 `STUDY`). 따로 두면 같은
  /// 결과를 주는 버튼이 두 개가 된다 — [ChallengeCategory] 참조.
  static const _categories = <ChallengeCategory?>[null, ...ChallengeCategory.filters];

  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();
  final _challenges = <Challenge>[];

  int _categoryIndex = 0;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _search();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || _reachedEnd || _loading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) _loadMore();
  }

  String? get _category => _categories[_categoryIndex]?.value;

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _reachedEnd = false;
    });
    try {
      final results = await ChallengeService.search(
        category: _category,
        keyword: _searchCtrl.text.trim(),
        page: 0,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _challenges
          ..clear()
          ..addAll(results);
        _page = 0;
        _reachedEnd = results.length < _pageSize;
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
      final results = await ChallengeService.search(
        category: _category,
        keyword: _searchCtrl.text.trim(),
        page: next,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _challenges.addAll(results);
        _page = next;
        _reachedEnd = results.length < _pageSize;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openChallenge(Challenge challenge) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TeamDetailScreen(challenge: challenge)));
    if (mounted) _search();
  }

  Future<void> _showCodeSheet() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _InviteCodeSheet(),
    );
    if (code == null || code.isEmpty || !mounted) return;

    try {
      final challenge = await ChallengeService.findByInviteCode(code);
      if (!mounted) return;
      if (challenge == null) {
        showBoosterToast(context, '해당 코드의 챌린지를 찾을 수 없어요.');
        return;
      }
      _openChallenge(challenge);
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '챌린지 탐색', trailing: CoinPill()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: BC.line),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 20, color: BC.ink3),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _search(),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: '챌린지 제목 또는 키워드',
                                hintStyle: TextStyle(fontSize: 14, color: BC.ink3),
                              ),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _showCodeSheet,
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                          color: BC.oSoft, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: const [
                          Icon(Icons.vpn_key_rounded, size: 18, color: BC.oMain),
                          SizedBox(width: 6),
                          Text('코드 참여',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: BC.oMain)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              // SelectChip은 세로 패딩 11+11에 글자 높이가 더해져 42를 넘는다.
              // 40으로 묶으면 글자 아래가 잘린다.
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => SelectChip(
                  label: _categories[i] == null
                      ? '전체'
                      : ChallengeCategory.labelOf(_categories[i]!.value),
                  selected: _categoryIndex == i,
                  onTap: () {
                    setState(() => _categoryIndex = i);
                    _search();
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
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
    if (_challenges.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
        children: const [
          Icon(Icons.search_off_rounded, size: 38, color: BC.ink3),
          SizedBox(height: 12),
          Center(
            child: Text('조건에 맞는 공개 챌린지가 없어요',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BC.ink2)),
          ),
          SizedBox(height: 6),
          Center(
            child: Text('비공개 챌린지는 초대 코드로 참여할 수 있어요.',
                style: TextStyle(fontSize: 13, color: BC.ink3)),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _search,
      color: BC.oMain,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
        itemCount: _challenges.length + (_reachedEnd ? 0 : 1),
        itemBuilder: (_, index) {
          if (index >= _challenges.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: BC.oMain, strokeWidth: 2.4),
                ),
              ),
            );
          }
          return _card(_challenges[index]);
        },
      ),
    );
  }

  Widget _card(Challenge challenge) {
    return GestureDetector(
      onTap: () => _openChallenge(challenge),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BC.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration:
                  BoxDecoration(gradient: BC.grad, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.flag_rounded, color: Colors.white70, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(challenge.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(challenge.description ?? '소개글이 없어요.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: BC.ink2)),
                  const SizedBox(height: 9),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    MiniTag(ChallengeCategory.labelOf(challenge.category)),
                    MiniTag('${challenge.durationDays}일'),
                    if (challenge.needsLeaderApproval)
                      const MiniTag('방장 승인', bg: BC.blueSoft, fg: BC.blue),
                  ]),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      const Icon(Icons.people_alt_rounded, size: 16, color: BC.ink3),
                      const SizedBox(width: 5),
                      Text('정원 ${challenge.maxParticipants}명',
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: BC.ink2)),
                      const Spacer(),
                      Text('예치 ${CoinPill.format(challenge.depositCoins)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4A4A4E))),
                      const SizedBox(width: 5),
                      const CoinDot(size: 16, symbol: '\$'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 초대 코드 입력 시트.
class _InviteCodeSheet extends StatefulWidget {
  const _InviteCodeSheet();
  @override
  State<_InviteCodeSheet> createState() => _InviteCodeSheetState();
}

class _InviteCodeSheetState extends State<_InviteCodeSheet> {
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            22, 14, 22, 22 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration:
                    BoxDecoration(color: BC.line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('초대 코드로 참여',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('비공개 챌린지는 방장이 공유한 코드로만 찾을 수 있어요.',
                style: TextStyle(fontSize: 13, color: BC.ink2)),
            const SizedBox(height: 18),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 6),
              decoration: InputDecoration(
                hintText: '코드 입력',
                hintStyle: const TextStyle(
                    color: BC.ink3, fontSize: 17, letterSpacing: 1, fontWeight: FontWeight.w600),
                filled: true,
                fillColor: BC.bg,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: BC.line, width: 1.5)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: BC.oMain, width: 1.5)),
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: '챌린지 찾기',
              onTap: () => Navigator.of(context).pop(_codeCtrl.text.trim()),
            ),
          ],
        ),
      ),
    );
  }
}
