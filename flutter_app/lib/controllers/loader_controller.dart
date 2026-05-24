import 'package:get/get.dart';

class LoaderController extends GetxController {
  final isLoading = false.obs;
  void startLoading() => isLoading.value = true;
  void stopLoading() => isLoading.value = false;
}
