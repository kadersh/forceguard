/**
 * ForceGuardHttpMock - HttpCalloutMock implementation for ForceGuard tests.
 * Returns a configurable mock response for any HTTP callout made during testing.
 * Used when RegressionTestExecutor or other classes make callouts to
 * the Salesforce Tooling API or external services.
 */
@IsTest
public class ForceGuardHttpMock implements HttpCalloutMock {

    private Integer statusCode;
    private String body;

    /**
     * Default constructor - returns 200 success.
     */
    public ForceGuardHttpMock() {
        this.statusCode = 200;
        this.body = '{"success": true}';
    }

    /**
     * Configurable constructor.
     * @param statusCode HTTP status code to return
     * @param body Response body
     */
    public ForceGuardHttpMock(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(statusCode);
        res.setBody(body);
        return res;
    }
}
