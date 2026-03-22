class ProductReportCount {
  final String productName;
  final int totalCount;
  final int unprocessedCount;

  const ProductReportCount({
    required this.productName,
    required this.totalCount,
    required this.unprocessedCount,
  });

  int get processedCount => totalCount - unprocessedCount;
}
