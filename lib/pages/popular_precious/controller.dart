import 'package:Pilipili/http/loading_state.dart';
import 'package:Pilipili/http/video.dart';
import 'package:Pilipili/models/model_hot_video_item.dart';
import 'package:Pilipili/models_new/popular/popular_precious/data.dart';
import 'package:Pilipili/pages/common/common_list_controller.dart';

class PopularPreciousController
    extends CommonListController<PopularPreciousData, HotVideoItemModel> {
  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  int? mediaId;

  @override
  List<HotVideoItemModel>? getDataList(PopularPreciousData response) {
    mediaId = response.mediaId;
    return response.list;
  }

  @override
  Future<LoadingState<PopularPreciousData>> customGetData() =>
      VideoHttp.popularPrecious(page: page);
}
