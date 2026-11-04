class FriendRequest {
  final String id;
  final String senderId;
  final String recipientId;
  final String senderName;
  final String recipientName;
  const FriendRequest({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.senderName,
    required this.recipientName,
  });
  factory FriendRequest.fromMap(String id, Map<String, dynamic> data) =>
      FriendRequest(
        id: id,
        senderId: data['senderId'] as String? ?? '',
        recipientId: data['recipientId'] as String? ?? '',
        senderName: data['senderName'] as String? ?? '',
        recipientName: data['recipientName'] as String? ?? '',
      );
}
