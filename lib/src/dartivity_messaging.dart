/*
 * Package : dartivity_messaging
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 27/11/2015
 * Copyright :  S.Hamblett 2015
 */

/// The messaging interface class. This class wraps the gcloud pubsub
/// packages and provides a simple send/recieve interface for DartivityMessage
/// classes.

part of dartivity_messaging;

class DartivityMessaging {
  DartivityMessaging(String dartivityId) {
    _dartivityId = dartivityId;
  }

  /// Authenticated
  bool _authenticated = false;

  /// Initialised
  bool _initialised = false;

  /// Ready, as in for use
  bool get ready => _authenticated && _initialised;

  /// Pubsub topic
  String _topic;

  String get topic => _topic;

  /// Pubsub subscription
  pubsub.Subscription _subscription;

  /// PubSub client
  pubsub.PubSub _pubsub;

  /// Dartivity client id
  String _dartivityId;

  /// Auth client, needed for closing
  auth.AutoRefreshingAuthClient _client;

  /// 409 indication for subscription
  final int _conflict = 409;

  /// initialise
  /// Initialises the messaging class.
  ///
  /// Must be called before class usage
  ///
  /// credentialsFile - Path to the credentials file
  /// which should be in JSON format
  /// projectName - The project name(actually the google project id)
  /// topic - the subscription topic
  Future<bool> initialise(String credentialsFile, String projectName, String topic) async {
    // Validation
    if (credentialsFile == null) {
      throw new DartivityMessagingException(
          DartivityMessagingException.noCredfileSpecified);
    }

    final String jsonCredentials = new File(credentialsFile).readAsStringSync();
    return initialiseJson(jsonCredentials, projectName, topic);
  }

  Future<bool> initialiseJson(String jsonCredentials, String projectName, String topic) async {
    if (projectName == null) {
      throw new DartivityMessagingException(
          DartivityMessagingException.noProjectnameSpecified);
    }

    if (topic == null) {
      throw new DartivityMessagingException(
          DartivityMessagingException.noTopicSpecified);
    }

    final Completer<bool> completer = new Completer<bool>();
    // Get the credentials file as a string and create a credentials class
    _topic = topic;

    final auth.ServiceAccountCredentials credentials =
        new auth.ServiceAccountCredentials.fromJson(jsonCredentials);

    // Create a scoped pubsub client with our authenticated credentials
    final List<String> scopes = []..addAll(pubsub.PubSub.SCOPES);
    _client = await auth.clientViaServiceAccount(credentials, scopes);
    _pubsub = new pubsub.PubSub(_client, projectName);
    _authenticated = true;

    // Subscribe to our topic, conflict means already subscribed from this client
    try {
      _subscription = await _pubsub.createSubscription(_dartivityId, topic);
    } catch (e) {
      if (e.status != _conflict) {
        throw new DartivityMessagingException(
            DartivityMessagingException.subscriptionFailed);
      } else {
        _subscription = await _pubsub.lookupSubscription(_dartivityId);
      }
    }
    _initialised = true;
    completer.complete(_initialised);
    return completer.future;
  }

  /// recieveRaw
  ///
  /// Recieve a message as String from our subscription
  ///
  /// wait - whether to wait for a message or not, default is not
  Future<String> receiveRaw({bool wait: false}) async {
    final Completer<String> completer = new Completer<String>();
    if (ready) {
      final pullEvent = await _subscription.pull(wait: wait);
      if (pullEvent != null) {
        await pullEvent.acknowledge();
        final String messageString = pullEvent.message.asString;
        completer.complete(messageString);
      }
      else {
        completer.complete(null);
      }
    }
    return completer.future;
  }

  /// recieve
  ///
  /// Recieve a message from our subscription
  ///
  /// wait - whether to wait for a message or not, default is not
  Future<DartivityMessage> receive({bool wait: false}) async {
    final Completer<DartivityMessage> completer =
        new Completer<DartivityMessage>();
    if (ready) {
      final pullEvent = await _subscription.pull(wait: wait);
      if (pullEvent != null) {
        await pullEvent.acknowledge();
        final String messageString = pullEvent.message.asString;
        try {
          final DartivityMessage dartivityMessage =
              new DartivityMessage.fromJSON(messageString);
          completer.complete(dartivityMessage);
        } catch (e) {
          completer.complete(null);
        }
      } else {
        completer.complete(null);
      }
    } else {
      completer.complete(null);
    }
    return completer.future;
  }

  /// send
  ///
  /// Send a message to our subscription
  ///
  /// message - the message string to send
  Future<DartivityMessage> send(DartivityMessage message) async {
    final Completer<DartivityMessage> completer =
        new Completer<DartivityMessage>();
    if (ready) {
      await _subscription.topic.publishString(message.toJSON());
      completer.complete(message);
    } else {
      completer.complete(null);
    }
    return completer.future;
  }

  /// close
  ///
  /// Close the messager. Default is to unsubscribe and deauth
  /// setting unsubscribe to false doesn't do the unsubscribe.
  void close([bool unsubscribe = true]) {
    // We don't need to wait, just assume pubsub will do this
    if (unsubscribe) {
      _subscription.delete();
    }
    _initialised = false;

    // Close the auth client
    _client.close();
    _authenticated = false;
  }
}
