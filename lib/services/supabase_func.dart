
import 'package:stock_submat/main.dart';

class SupabaseFunc{
  Future<List<Map<String, dynamic>>> fetchSrn(String tablename, String items, String conditions, String groupby) async{
    final data = await supabase.rpc('select_groupby', params: {
      'table_name': tablename, 
      'select_item': items, 
      'conditions': conditions,
      'group_by': groupby
      });

    if(data != null && data is List){
      return List<Map<String, dynamic>>.from(data);
    } else {
      return [];
    }
  }

  Future<List<String>> fetchDocRefList({String? search, int limit = 200}) async {
    final trimmed = (search ?? '').trim().toUpperCase();
    final List<dynamic> rows = await supabase
        .from('fb_srn')
        .select('doc_ref')
        .eq('is_confirm', false)
        .not('doc_ref', 'is', null)
        .limit(limit);

    final docRefs = <String>{};
    for (final row in rows) {
      if (row is Map && row['doc_ref'] != null) {
        final ref = row['doc_ref'].toString();
        if (trimmed.isEmpty || ref.toUpperCase().contains(trimmed)) {
          docRefs.add(ref);
        }
      }
    }
    final result = docRefs.toList()..sort();
    return result;
  }

  Future<void> confirmSrnLocator({
    required String docRef,
    required String locator,
  }) async {
    await supabase
        .from('fb_srn')
        .update({'is_confirm': true})
        .eq('doc_ref', docRef)
        .eq('locator', locator);
  }
}