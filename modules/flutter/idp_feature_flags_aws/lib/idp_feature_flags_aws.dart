/// AWS-backed flag source for `idp_feature_flags`.
///
/// Reads a flag document published to S3 and served through CloudFront, with
/// client-side targeting: attribute rules and percentage rollouts evaluated on
/// device, so no AWS credentials ship in the app.
library;

export 'src/aws_flag_source.dart';
export 'src/evaluation_context.dart';
export 'src/flag_document.dart';
export 'src/targeting.dart';
