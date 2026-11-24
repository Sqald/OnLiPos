/// 会員・クーポン・厨房・客用表示・勤怠・予約・棚卸・入荷・会計取消のAPIクライアント。
library;

import 'package:onlipos/api/pos_api_client.dart';

class SaleExtrasApi {
  static Future<Map<String, dynamic>> findCustomer(String query) =>
      PosApiClient.request('GET', '/api/v1/customers', query: {'q': query});

  static Future<Map<String, dynamic>> createCustomer({
    required String name,
    String? phone,
  }) => PosApiClient.request(
    'POST',
    '/api/v1/customers',
    body: {'name': name, 'phone': ?phone},
  );

  static Future<Map<String, dynamic>> checkCoupon(String code, int total) =>
      PosApiClient.request(
        'GET',
        '/api/v1/coupons/${Uri.encodeComponent(code)}',
        query: {'total': total.toString()},
      );

  static Future<Map<String, dynamic>> sales({
    required int employeeId,
    required String date,
  }) => PosApiClient.request(
    'GET',
    '/api/v1/sales',
    query: {'employee_id': employeeId.toString(), 'date': date},
  );

  static Future<Map<String, dynamic>> voidSale({
    required int saleId,
    required List<int> employeeIds,
    required String reason,
  }) => PosApiClient.request(
    'POST',
    '/api/v1/sales/$saleId/void',
    body: {'employee_ids': employeeIds, 'reason': reason},
  );

  static Future<Map<String, dynamic>> sendKitchen({
    required String requestId,
    String? tableNumber,
    required List<Map<String, dynamic>> items,
  }) => PosApiClient.request(
    'POST',
    '/api/v1/kitchen_orders',
    body: {
      'client_request_id': requestId,
      'table_number': ?tableNumber,
      'items': items,
    },
  );

  static Future<Map<String, dynamic>> kitchenOrders() =>
      PosApiClient.request('GET', '/api/v1/kitchen_orders');

  static Future<Map<String, dynamic>> updateKitchenOrder(
    int id,
    String event,
  ) => PosApiClient.request(
    'PATCH',
    '/api/v1/kitchen_orders/$id',
    body: {'event': event},
  );

  static Future<Map<String, dynamic>> customerDisplayUrl() =>
      PosApiClient.request('GET', '/api/v1/customer_display');

  static Future<Map<String, dynamic>> updateCustomerDisplay({
    required List<Map<String, dynamic>> items,
    required int total,
    String message = '',
  }) => PosApiClient.request(
    'PUT',
    '/api/v1/customer_display',
    body: {'items': items, 'total': total, 'message': message},
    timeout: const Duration(seconds: 3),
  );

  static Future<Map<String, dynamic>> attendances() =>
      PosApiClient.request('GET', '/api/v1/attendances');

  static Future<Map<String, dynamic>> punch({
    required String code,
    required String pin,
    required String punch,
  }) => PosApiClient.request(
    'POST',
    '/api/v1/attendances',
    body: {'code': code, 'pin': pin, 'punch': punch},
  );

  static Future<Map<String, dynamic>> reservations(String date) =>
      PosApiClient.request(
        'GET',
        '/api/v1/reservations',
        query: {'date': date},
      );

  static Future<Map<String, dynamic>> updateReservation(
    int id,
    String status,
  ) => PosApiClient.request(
    'PATCH',
    '/api/v1/reservations/$id',
    body: {'status': status},
  );

  static Future<Map<String, dynamic>> stocktakes() =>
      PosApiClient.request('GET', '/api/v1/stocktakes');

  static Future<Map<String, dynamic>> countStock({
    required int stocktakeId,
    required int employeeId,
    required String code,
    required int quantity,
    required bool add,
  }) => PosApiClient.request(
    'POST',
    '/api/v1/stocktakes/$stocktakeId/count',
    body: {
      'employee_id': employeeId,
      'jan_code': code,
      'quantity': quantity,
      'add': add,
    },
  );

  static Future<Map<String, dynamic>> purchaseOrders() =>
      PosApiClient.request('GET', '/api/v1/purchase_orders');

  static Future<Map<String, dynamic>> purchaseOrder(int id) =>
      PosApiClient.request('GET', '/api/v1/purchase_orders/$id');

  static Future<Map<String, dynamic>> receive({
    required int orderId,
    required int employeeId,
    required Map<String, int> received,
  }) => PosApiClient.request(
    'POST',
    '/api/v1/purchase_orders/$orderId/receive',
    body: {'employee_id': employeeId, 'received': received},
  );
}
