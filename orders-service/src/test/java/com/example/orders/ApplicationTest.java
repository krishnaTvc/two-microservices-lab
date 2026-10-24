package com.example.orders;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ApplicationTest {
    @LocalServerPort
    private int port;
    private final HttpClient client = HttpClient.newHttpClient();

    private HttpResponse<String> get(String path) throws Exception {
        return client.send(HttpRequest.newBuilder(
            URI.create("http://127.0.0.1:" + port + path)).GET().build(),
            HttpResponse.BodyHandlers.ofString());
    }

    @Test
    void servesBrowserPage() throws Exception {
        var response = get("/");
        assertEquals(200, response.statusCode());
        assertTrue(response.body().contains("<h1>Hello from Orders Service!</h1>"));
        assertTrue(response.body().contains("/api/hello"));
    }

    @Test
    void returnsHelloJson() throws Exception {
        var response = get("/api/hello");
        assertEquals(200, response.statusCode());
        assertTrue(response.headers().firstValue("content-type").orElse("").contains("application/json"));
        assertTrue(response.body().contains("Hello from Orders Service!"));
        assertTrue(response.body().contains("orders-service"));
    }

    @Test
    void exposesHealthForDeployment() throws Exception {
        var response = get("/health");
        assertEquals(200, response.statusCode());
        assertEquals("UP", response.body());
    }
}
