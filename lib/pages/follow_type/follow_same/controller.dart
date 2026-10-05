import 'package:Pilipili/http/loading_state.dart';
import 'package:Pilipili/http/user.dart';
import 'package:Pilipili/models_new/follow/data.dart';
import 'package:Pilipili/pages/follow_type/controller.dart';

class FollowSameController extends FollowTypeController {
  @override
  Future<LoadingState<FollowData>> customGetData() =>
      UserHttp.sameFollowing(mid: mid, pn: page);
}
