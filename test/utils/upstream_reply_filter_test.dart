import 'dart:io';

import 'package:Pilipili/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:Pilipili/grpc/reply.dart';
import 'package:Pilipili/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pili-reply-filter-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
  });
  setUp(() {
    ReplyGrpc.blockAtOnlyReply = false;
    ReplyGrpc.blockReplyAtCount = null;
    ReplyGrpc.antiGoodsReply = false;
    ReplyGrpc.enableFilter = false;
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  ReplyInfo reply(String message, {bool nested = false}) => ReplyInfo(
    root: Int64(1),
    parent: Int64(nested ? 2 : 1),
    content: Content(
      message: message,
      atNameToMid: {'甲': Int64(10), '乙': Int64(20)}.entries,
    ),
  );
  test('mention count threshold applies only when enabled', () {
    expect(ReplyGrpc.needRemoveGrpc(reply('@甲 @乙 看这里')), isFalse);
    ReplyGrpc.blockReplyAtCount = 2;
    expect(ReplyGrpc.needRemoveGrpc(reply('@甲 @乙 看这里')), isTrue);
    ReplyGrpc.blockReplyAtCount = 3;
    expect(ReplyGrpc.needRemoveGrpc(reply('@甲 @乙 看这里')), isFalse);
  });
  test(
    'mention-only filtering preserves actual discussion and unknown mentions',
    () {
      ReplyGrpc.blockAtOnlyReply = true;
      expect(ReplyGrpc.needRemoveGrpc(reply('@甲 @乙\n')), isTrue);
      expect(ReplyGrpc.needRemoveGrpc(reply('@甲 这个解释不错')), isFalse);
      expect(ReplyGrpc.needRemoveGrpc(reply('@未知用户')), isFalse);
      expect(
        ReplyGrpc.needRemoveGrpc(reply('回复 @甲: @乙', nested: true)),
        isTrue,
      );
      expect(
        ReplyGrpc.needRemoveGrpc(reply('回复 @甲: 赞同', nested: true)),
        isFalse,
      );
    },
  );
}
