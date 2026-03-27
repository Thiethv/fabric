
import 'package:stock_fabric/main.dart';

class SupabaseFunc{
  Future<List<Map<String, dynamic>>> fetchSrn({
    String? searchText,
    String? planDate,
    required bool isConfirmed,
  }) async {
    var query = supabase
        .from('fb_srn')
        .select(
          'id, doc_ref, locator, qty, req_qty, is_confirm, created_at, '
          'confirm_date, is_priority, plan_date',
        )
        .eq('is_confirm', isConfirmed);

    final normalizedSearch = searchText?.trim();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      query = query.ilike('doc_ref', '%$normalizedSearch%');
    }

    if (planDate != null && planDate.isNotEmpty) {
      query = query.eq('plan_date', planDate);
    }

    final data = await query
        .order(isConfirmed ? 'confirm_date' : 'doc_ref', ascending: !isConfirmed)
        .order('locator')
        .order('id');

    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> confirmSrn(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }

    await supabase
        .from('fb_srn')
        .update({
          'is_confirm': true,
          'confirm_date': DateTime.now().toUtc().toIso8601String(),
        })
        .inFilter('id', ids);
  }
}