import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show RouteInformation, RouteInformationParser;
import 'package:path/path.dart' as p;

import '../../matcher/route_matcher.dart';

final _hostRegex = RegExp(
    r'^(?:[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?\.)+[a-z\d][a-z\d-]{0,61}[a-z\d]$');

/// AutoRoute extension of [RouteInformationParser]
class DefaultRouteParser extends RouteInformationParser<UrlState> {
  final RouteMatcher _matcher;

  /// If set to true all paths that's
  /// matched as prefix will be included in
  /// matching list.
  /// Passed to [RouteMatcher.matchUri]
  final bool includePrefixMatches;

  /// Default constructor
  DefaultRouteParser(this._matcher, {this.includePrefixMatches = false});

  @override
  Future<UrlState> parseRouteInformation(RouteInformation routeInformation) {
    final resolvedUri = _normalize(routeInformation.uri);
    var matches = _matcher.matchUri(resolvedUri,
        includePrefixMatches: includePrefixMatches);
    return SynchronousFuture<UrlState>(
      UrlState(routeInformation.uri, matches ?? const [],
          pathState: routeInformation.state),
    );
  }

  /// deep-links with customs schemes that have no actual host
  /// like `myapp://books/1` will not consider the host as part of the path
  /// that's why we need to normalize the path by adding the host as a prefix
  Uri _normalize(Uri uri) {
    var path = uri.path.isEmpty ? '/' : uri.path;

    /// whether to treat the host as part of the path
    if (!_hostRegex.hasMatch(uri.host)) {
      path = p.normalize('/${uri.host}${uri.path}');
    }
    return Uri(
      path: path,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
  }

  @override
  RouteInformation restoreRouteInformation(UrlState configuration) {
    return AutoRouteInformation(
      uri: configuration.url.isEmpty ? Uri(path: '/') : configuration.uri,
      replace: configuration.shouldReplace,
      state: configuration.pathState,
    );
  }
}

/// An extended type of [RouteInformation] that holds
/// an extra property [replace] which forces the current
/// route to be replaced
class AutoRouteInformation extends RouteInformation {
  /// forces the current location to be replaced with this location
  final bool replace;

  /// Default constructor
  const AutoRouteInformation({
    required Uri super.uri,
    super.state,
    this.replace = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoRouteInformation &&
          runtimeType == other.runtimeType &&
          uri == other.uri &&
          state == other.state;

  @override
  int get hashCode => replace.hashCode;
}

/// [UrlState] Holds current url state in a more structured way
/// it's used by [Router] as configuration state
@immutable
class UrlState {
  /// Represents current router uri
  final Uri uri;

  /// The list of segments representing the current [uri]
  final List<RouteMatch> segments;

  /// This is passed to [AutoRouteInformation.replace]
  /// when location is restored
  final bool shouldReplace;

  /// Holds instance of browser entry-state
  final Object? pathState;

  /// Default constructor
  const UrlState(
    this.uri,
    this.segments, {
    this.shouldReplace = false,
    this.pathState,
  });

  /// Returns a fully decoded [uri]
  String get url => Uri.decodeFull(uri.toString());

  /// Returns the path of [uri]
  String get path => uri.path;

  /// Builds UrlState from list of
  /// route matches instead of uri
  factory UrlState.fromSegments(
    List<RouteMatch> routes, {
    bool shouldReplace = false,
    Object? state,
  }) {
    return UrlState(
      _buildUri(routes),
      routes,
      shouldReplace: shouldReplace,
      pathState: state,
    );
  }

  /// Converts a list of linear route matches to
  /// to a hierarchy of routes
  /// e.g [Match1,Match2,Match3]
  /// will be [Match1[Match2[Match3]]]
  static RouteMatch toHierarchy(List<RouteMatch> segments) {
    if (segments.length == 1) {
      return segments.first;
    } else {
      return segments.first.copyWith(children: [
        toHierarchy(
          segments.sublist(1, segments.length),
        ),
      ]);
    }
  }

  /// Returns a new instance of [UrlState]
  /// With the flattened version of [segments]
  /// e.g if segments = [Match1[Match2[Match3]]]
  /// the result is [Match1,Match2,Match3]
  UrlState get flatten =>
      UrlState.fromSegments(segments.last.flattened, state: pathState);

  @override
  String toString() {
    return 'UrlState{uri: $uri, shouldReplace: $shouldReplace, pathState: $pathState}';
  }

  /// Returns true if [segments] is not empty
  bool get hasSegments => segments.isNotEmpty;

  /// Returns to topMost item in the segments list
  /// Witch is the last
  RouteMatch? get topMatch => hasSegments ? segments.last : null;

  RouteMatch? _findSegment(
    List<RouteMatch> segments,
    bool Function(RouteMatch segment) predicate,
  ) {
    for (var segment in segments) {
      if (predicate(segment)) {
        return segment;
      } else if (segment.hasChildren) {
        var subSegment = _findSegment(segment.children!, predicate);
        if (subSegment != null) {
          return subSegment;
        }
      }
    }
    return null;
  }

  /// re
  List<RouteMatch> childrenOfSegmentNamed(String routeName) {
    return _findSegment(segments, (match) => match.name == routeName)
            ?.children ??
        const [];
  }

  static Uri _buildUri(List<RouteMatch> routes) {
    var fullPath = '/';
    if (routes.isEmpty) {
      return Uri(path: fullPath);
    }
    fullPath = p.joinAll(
      routes.where((e) => e.stringMatch.isNotEmpty).map(
            (e) => e.stringMatch,
          ),
    );
    final normalized = p.normalize(fullPath);
    final lastSegment = routes.last;
    Map<String, dynamic> queryParams = {};
    if (lastSegment.queryParams.isNotEmpty) {
      var queries = lastSegment.queryParams.rawMap;

      for (var key in queries.keys) {
        var value = _normalizeQueryParamValue(queries[key]);
        if (value != null) {
          queryParams[key] = value;
        }
      }
    }

    String? fragment;
    if (lastSegment.fragment.isNotEmpty == true) {
      fragment = lastSegment.fragment;
    }
    return Uri(
      path: normalized,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
      fragment: fragment,
    );
  }

  static dynamic _normalizeQueryParamValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Iterable) {
      return value.map((el) => el?.toString()).toList();
    }
    if (value is! String) {
      value = value.toString();
    }
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UrlState &&
          runtimeType == other.runtimeType &&
          pathState == other.pathState &&
          const ListEquality().equals(segments, other.segments);

  @override
  int get hashCode => const ListEquality().hash(segments) ^ pathState.hashCode;

  /// Returns a new [UrlState] instance
  /// with replaced properties
  UrlState copyWith({
    List<RouteMatch>? segments,
    Uri? uri,
    bool? shouldReplace,
    Object? pathState,
  }) {
    return UrlState(
      uri ?? this.uri,
      segments ?? this.segments,
      shouldReplace: shouldReplace ?? this.shouldReplace,
      pathState: pathState ?? this.pathState,
    );
  }
}
