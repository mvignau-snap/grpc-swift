/*
 * Copyright 2019, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import NIO
import NIOHTTP2
import Logging

/// A bidirectional-streaming gRPC call. Each response is passed to the provided observer block.
///
/// Messages should be sent via the `send` method; an `.end` message should be sent
/// to indicate the final message has been sent.
///
/// The following futures are available to the caller:
/// - `initialMetadata`: the initial metadata returned from the server,
/// - `status`: the status of the gRPC call after it has ended,
/// - `trailingMetadata`: any metadata returned from the server alongside the `status`.
public final class BidirectionalStreamingCall<RequestPayload: GRPCPayload, ResponsePayload: GRPCPayload>
  : BaseClientCall<RequestPayload, ResponsePayload>,
    StreamingRequestClientCall {
  private var messageQueue: EventLoopFuture<Void>

  init(
    path: String,
    scheme: String,
    authority: String,
    callOptions: CallOptions,
    eventLoop: EventLoop,
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger,
    handler: @escaping (ResponsePayload) -> Void
  ) {
    self.messageQueue = eventLoop.makeSucceededFuture(())
    let requestID = callOptions.requestIDProvider.requestID()
    var logger = logger
    logger[metadataKey: MetadataKey.requestID] = "\(requestID)"
    logger.debug("starting rpc", metadata: ["path": "\(path)"])

    let responseHandler = GRPCClientStreamingResponseChannelHandler(
      initialMetadataPromise: eventLoop.makePromise(),
      trailingMetadataPromise: eventLoop.makePromise(),
      statusPromise: eventLoop.makePromise(),
      errorDelegate: errorDelegate,
      timeout: callOptions.timeout,
      logger: logger,
      responseHandler: handler
    )

    let requestHead = _GRPCRequestHead(
      scheme: scheme,
      path: path,
      host: authority,
      requestID: requestID,
      options: callOptions
    )

    let requestHandler = _StreamingRequestChannelHandler<RequestPayload>(requestHead: requestHead)

    super.init(
      eventLoop: eventLoop,
      multiplexer: multiplexer,
      callType: .bidirectionalStreaming,
      callOptions: callOptions,
      responseHandler: responseHandler,
      requestHandler: requestHandler,
      logger: logger
    )
  }

  public func newMessageQueue() -> EventLoopFuture<Void> {
    return self.messageQueue
  }
}
