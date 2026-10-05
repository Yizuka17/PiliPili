import 'package:Pilipili/http/loading_state.dart';
import 'package:Pilipili/http/user.dart';
import 'package:Pilipili/models_new/follow/data.dart';
import 'package:Pilipili/pages/follow_type/controller.dart';

class FollowedController extends FollowTypeController {
  @override
  Future<LoadingState<FollowData>> customGetData() =>
      UserHttp.followedUp(mid: mid, pn: page);
}
