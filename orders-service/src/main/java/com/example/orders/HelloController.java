package com.example.orders;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {
    @GetMapping("/api/hello")
    public Map<String, String> hello() {
        return Map.of("service", "orders-service", "message", "Hello from Orders Service!");
    }

    @GetMapping(value = "/health", produces = "text/plain")
    public String health() {
        return "UP";
    }
}
