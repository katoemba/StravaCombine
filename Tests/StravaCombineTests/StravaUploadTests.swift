import XCTest
import Mocker
import Combine
@testable import StravaCombine

final class StravaUploadTests: XCTestCase {
    private var cancellable: AnyCancellable?
    
    /// Test the upload of a file to Strava, and check that the upload is completed
    func testUpload() {
        var uploadId = Int64(1000)
        let accessToken = "512352345245345346346346"
        let activityId = Int64(19001)
        let inProgressStatus = "Your activity is still being processed."
        let completionStatus = "Your activity is ready."

        // Part 1: upload and mock that strava is processing
        let uploadPostExpectation = expectation(description: "The upload POST mock should be called")
        let uploadPostEndpoint = URL(string: "https://www.strava.com/api/v3/uploads")!
        var uploadPostMock = Mock(url: uploadPostEndpoint, dataType: .json, statusCode: 200, data: [.post: MockedData.uploadProgressJSON(id: uploadId, status: inProgressStatus)])
        uploadPostMock.delay = DispatchTimeInterval.milliseconds(400)
        uploadPostMock.onRequest = { request, postBodyArguments in
            // Check that the access token is passed correctly
            XCTAssertEqual(request.allHTTPHeaderFields?["Authorization"], "Bearer \(accessToken)")
        }
        uploadPostMock.completion = {
            // Confirm that the upload was called
            uploadPostExpectation.fulfill()
        }
        uploadPostMock.register()

        // Set the number of times to return that strava is reporting that the processing is in progress
        let stravaInProgressCount = 2
        let uploadGetProgressExpectation = expectation(description: "The upload progress mock should be called \(stravaInProgressCount) times")
        uploadGetProgressExpectation.expectedFulfillmentCount = stravaInProgressCount

        let uploadProgressEndpoint = URL(string: "https://www.strava.com/api/v3/uploads/\(uploadId)")!
        var uploadProgressMock = Mock(url: uploadProgressEndpoint, dataType: .json, statusCode: 200, data: [.get: MockedData.uploadProgressJSON(id: uploadId, status: inProgressStatus)])
        uploadProgressMock.delay = DispatchTimeInterval.milliseconds(100)
        uploadProgressMock.completion = {
            // Confirm that the upload check was called
            uploadGetProgressExpectation.fulfill()
        }
        uploadProgressMock.register()

        let publishUploadStatusExpectation = expectation(description: "The upload status shall be published")
        publishUploadStatusExpectation.expectedFulfillmentCount = stravaInProgressCount
        let publishUploadStatusFinishedExpectation = expectation(description: "The upload status publisher shall be marked finished")
        let uploadActivityIdPresentExpectation = expectation(description: "The activity id shall be present")

        let stravaUpload = StravaUpload(StravaConfig(client_id: "client", client_secret: "secret"))
        cancellable = stravaUpload.uploadGpx(Data(), activityType: .run, accessToken: accessToken)
            .sink(receiveCompletion: { (completion) in
                switch completion {
                case .finished:
                    // Confirm that the publisher is finished
                    publishUploadStatusFinishedExpectation.fulfill()
                case .failure(_):
                    XCTAssert(false, "expected .finish completion instead of .failure")
                }
            }) { (upload) in
                if let uploadActivityId = upload.activity_id {
                    // Validate that the expected activity id is reported back
                    XCTAssertEqual(uploadActivityId, activityId)
                    XCTAssertEqual(completionStatus, upload.status)

                    // Confirm that an activity id was reported.
                    uploadActivityIdPresentExpectation.fulfill()
                }
                else {
                    uploadId = upload.id
                    XCTAssertEqual(inProgressStatus, upload.status)
                    
                    // Confirm that a status update was published.
                    publishUploadStatusExpectation.fulfill()
                }
            }

        /// Verify that upload is called, that progress is called a number of times, and that the same number of times that status is passed to the subscriber.
        wait(for: [uploadPostExpectation, uploadGetProgressExpectation, publishUploadStatusExpectation], timeout: 10.0, enforceOrder: true)

        // Remove the mocks and now expect that upload and activity id are fulfilled
        Mocker.removeAll()

        // Part 2: register a mock that reports an activity id, and check that the publisher finishes
        let uploadFinalGetProgressExpectation = expectation(description: "The final upload completed mock should be called")
        let uploadFinalProgressEndpoint = URL(string: "https://www.strava.com/api/v3/uploads/\(uploadId)")!
        var uploadsFinalProgressMock = Mock(url: uploadFinalProgressEndpoint, dataType: .json, statusCode: 200, data: [.get: MockedData.uploadCompletedJSON(id: uploadId, activityId: activityId, status: completionStatus)])
        uploadsFinalProgressMock.delay = DispatchTimeInterval.milliseconds(100)
        uploadsFinalProgressMock.completion = {
            uploadFinalGetProgressExpectation.fulfill()
        }
        uploadsFinalProgressMock.register()
        
        wait(for: [uploadFinalGetProgressExpectation, uploadActivityIdPresentExpectation, publishUploadStatusFinishedExpectation], timeout: 2.0, enforceOrder: true)
    }
    
    func testDuplicateUpload() {
        let uploadId = Int64(1000)
        let accessToken = "512352345245345346346346"
        let inProgressStatus = "Your activity is still being processed."
        let completionStatus = "There was an error processing your activity."
        let completionError = "workout.gpx duplicate of activity 3888037200"

        // Part 1: upload and mock that strava is processing
        let uploadPostExpectation = expectation(description: "The upload POST mock should be called")
        let uploadPostEndpoint = URL(string: "https://www.strava.com/api/v3/uploads")!
        var uploadPostMock = Mock(url: uploadPostEndpoint, dataType: .json, statusCode: 200, data: [.post: MockedData.uploadProgressJSON(id: uploadId, status: inProgressStatus)])
        uploadPostMock.delay = DispatchTimeInterval.milliseconds(400)
        uploadPostMock.onRequest = { request, postBodyArguments in
            // Check that the access token is passed correctly
            XCTAssertEqual(request.allHTTPHeaderFields?["Authorization"], "Bearer \(accessToken)")
        }
        uploadPostMock.completion = {
            // Confirm that the upload was called
            uploadPostExpectation.fulfill()
        }
        uploadPostMock.register()

        // Set the number of times to return that strava is reporting that the processing is in progress
        let stravaInProgressCount = 2
        let uploadGetProgressExpectation = expectation(description: "The upload progress mock should be called \(stravaInProgressCount) times")
        uploadGetProgressExpectation.expectedFulfillmentCount = stravaInProgressCount

        let uploadProgressEndpoint = URL(string: "https://www.strava.com/api/v3/uploads/\(uploadId)")!
        var uploadProgressMock = Mock(url: uploadProgressEndpoint, dataType: .json, statusCode: 200, data: [.get: MockedData.uploadProgressJSON(id: uploadId, status: inProgressStatus)])
        uploadProgressMock.delay = DispatchTimeInterval.milliseconds(100)
        uploadProgressMock.completion = {
            // Confirm that the upload check was called
            uploadGetProgressExpectation.fulfill()
        }
        uploadProgressMock.register()

        var expectUploadStatus = true
        let publishUploadStatusExpectation = expectation(description: "The upload status shall be published")
        publishUploadStatusExpectation.expectedFulfillmentCount = stravaInProgressCount
        let publishUploadStatusFailureExpectation = expectation(description: "The upload status publisher shall be marked as failed")

        let stravaUpload = StravaUpload(StravaConfig(client_id: "client", client_secret: "secret"))
        cancellable = stravaUpload.uploadGpx(Data(), activityType: .run, accessToken: accessToken)
            .sink(receiveCompletion: { (completion) in
                switch completion {
                case .finished:
                    XCTAssert(false, "expected .failure completion instead of .finish")
                case let .failure(error):
                    XCTAssertEqual(error.localizedDescription, completionError)
                    // Confirm that the publisher is failed
                    publishUploadStatusFailureExpectation.fulfill()
                }
            }) { (upload) in
                XCTAssertEqual(true, expectUploadStatus)
                publishUploadStatusExpectation.fulfill()
            }

        /// Verify that upload is called, that progress is called a number of times, and that the same number of times that status is passed to the subscriber.
        wait(for: [uploadPostExpectation, uploadGetProgressExpectation, publishUploadStatusExpectation], timeout: 10.0, enforceOrder: true)

        // Remove the mocks and now expect that failure is fulfilled
        Mocker.removeAll()
        expectUploadStatus = false

        // Part 2: register a mock that reports an activity id, and check that the publisher finishes
        let uploadFinalGetProgressExpectation = expectation(description: "The final upload completed mock should be called")
        let uploadFinalProgressEndpoint = URL(string: "https://www.strava.com/api/v3/uploads/\(uploadId)")!
        var uploadsFinalProgressMock = Mock(url: uploadFinalProgressEndpoint, dataType: .json, statusCode: 200, data: [.get: MockedData.uploadErrorJSON(id: uploadId, status: completionStatus, error: completionError)])
        uploadsFinalProgressMock.delay = DispatchTimeInterval.milliseconds(100)
        uploadsFinalProgressMock.completion = {
            uploadFinalGetProgressExpectation.fulfill()
        }
        uploadsFinalProgressMock.register()
        
        wait(for: [uploadFinalGetProgressExpectation, publishUploadStatusFailureExpectation], timeout: 2.0, enforceOrder: true)
    }

    func testUploadFailure() {
        let uploadId = Int64(1000)
        let accessToken = "512352345245345346346346"
        let inProgressStatus = "Your activity is still being processed."
        let completionStatus = "There was an error processing your activity."
        let completionError = "workout.gpx duplicate of activity 3888037200"

        // Part 1: upload and mock that strava is processing
        let uploadPostExpectation = expectation(description: "The upload POST mock should be called")
        let uploadPostEndpoint = URL(string: "https://www.strava.com/api/v3/uploads")!
        var uploadPostMock = Mock(url: uploadPostEndpoint, dataType: .json, statusCode: 200, data: [.post: MockedData.uploadProgressJSON(id: uploadId, status: inProgressStatus)])
        uploadPostMock.delay = DispatchTimeInterval.milliseconds(400)
        uploadPostMock.onRequest = { request, postBodyArguments in
            // Check that the access token is passed correctly
            XCTAssertEqual(request.allHTTPHeaderFields?["Authorization"], "Bearer \(accessToken)")
        }
        uploadPostMock.completion = {
            // Confirm that the upload was called
            uploadPostExpectation.fulfill()
        }
        uploadPostMock.register()

        // Set the number of times to return that strava is reporting that the processing is in progress
        let stravaInProgressCount = 2
        let uploadGetProgressExpectation = expectation(description: "The upload progress mock should be called \(stravaInProgressCount) times")
        uploadGetProgressExpectation.expectedFulfillmentCount = stravaInProgressCount

        let uploadProgressEndpoint = URL(string: "https://www.strava.com/api/v3/uploads/\(uploadId)")!
        var uploadProgressMock = Mock(url: uploadProgressEndpoint, dataType: .json, statusCode: 200, data: [.get: MockedData.uploadProgressJSON(id: uploadId, status: inProgressStatus)])
        uploadProgressMock.delay = DispatchTimeInterval.milliseconds(100)
        uploadProgressMock.completion = {
            // Confirm that the upload check was called
            uploadGetProgressExpectation.fulfill()
        }
        uploadProgressMock.register()

        var expectUploadStatus = true
        let publishUploadStatusExpectation = expectation(description: "The upload status shall be published")
        publishUploadStatusExpectation.expectedFulfillmentCount = stravaInProgressCount
        let publishUploadStatusFailureExpectation = expectation(description: "The upload status publisher shall be marked as failed")

        let stravaUpload = StravaUpload(StravaConfig(client_id: "client", client_secret: "secret"))
        cancellable = stravaUpload.uploadGpx(Data(), activityType: .run, accessToken: accessToken)
            .sink(receiveCompletion: { (completion) in
                switch completion {
                case .finished:
                    XCTAssert(false, "expected .failure completion instead of .finish")
                case let .failure(error):
                    XCTAssertEqual(error.localizedDescription, completionError)
                    // Confirm that the publisher is failed
                    publishUploadStatusFailureExpectation.fulfill()
                }
            }) { (upload) in
                XCTAssertEqual(true, expectUploadStatus)
                publishUploadStatusExpectation.fulfill()
            }

        /// Verify that upload is called, that progress is called a number of times, and that the same number of times that status is passed to the subscriber.
        wait(for: [uploadPostExpectation, uploadGetProgressExpectation, publishUploadStatusExpectation], timeout: 10.0, enforceOrder: true)

        // Remove the mocks and now expect that failure is fulfilled
        Mocker.removeAll()
        expectUploadStatus = false

        // Part 2: register a mock that reports an activity id, and check that the publisher finishes
        let uploadFinalGetProgressExpectation = expectation(description: "The final upload completed mock should be called")
        let uploadFinalProgressEndpoint = URL(string: "https://www.strava.com/api/v3/uploads/\(uploadId)")!
        var uploadsFinalProgressMock = Mock(url: uploadFinalProgressEndpoint, dataType: .json, statusCode: 200, data: [.get: MockedData.uploadErrorJSON(id: uploadId, status: completionStatus, error: completionError)])
        uploadsFinalProgressMock.delay = DispatchTimeInterval.milliseconds(100)
        uploadsFinalProgressMock.completion = {
            uploadFinalGetProgressExpectation.fulfill()
        }
        uploadsFinalProgressMock.register()
        
        wait(for: [uploadFinalGetProgressExpectation, publishUploadStatusFailureExpectation], timeout: 2.0, enforceOrder: true)
    }

    func testUploadBadRequest() {
        let accessToken = "512352345245345346346346"
        let completionError = "Bad Request"

        // Part 1: upload and mock that strava is processing
        let uploadPostExpectation = expectation(description: "The upload POST mock should be called")
        let uploadPostEndpoint = URL(string: "https://www.strava.com/api/v3/uploads")!
        var uploadPostMock = Mock(url: uploadPostEndpoint, dataType: .json, statusCode: 200, data: [.post: MockedData.uploadErrorBadRequest(message: completionError)])
        uploadPostMock.delay = DispatchTimeInterval.milliseconds(400)
        uploadPostMock.onRequest = { request, postBodyArguments in
            // Check that the access token is passed correctly
            XCTAssertEqual(request.allHTTPHeaderFields?["Authorization"], "Bearer \(accessToken)")
        }
        uploadPostMock.completion = {
            // Confirm that the upload was called
            uploadPostExpectation.fulfill()
        }
        uploadPostMock.register()

        let expectUploadStatus = false
        let publishUploadStatusFailureExpectation = expectation(description: "The upload status publisher shall be marked as failed")

        let stravaUpload = StravaUpload(StravaConfig(client_id: "client", client_secret: "secret"))
        cancellable = stravaUpload.uploadGpx(Data(), activityType: .run, accessToken: accessToken)
            .sink(receiveCompletion: { (completion) in
                switch completion {
                case .finished:
                    XCTAssert(false, "expected .failure completion instead of .finish")
                case let .failure(error):
                    XCTAssertEqual(error.localizedDescription, completionError)
                    // Confirm that the publisher is failed
                    publishUploadStatusFailureExpectation.fulfill()
                }
            }) { (upload) in
                XCTAssertEqual(true, expectUploadStatus)
            }

        /// Verify that upload is called, and that the upload fails.
        wait(for: [uploadPostExpectation, publishUploadStatusFailureExpectation], timeout: 2.0, enforceOrder: true)
    }
}
