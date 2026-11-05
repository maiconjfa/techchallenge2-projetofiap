// demo(gitops): OTel instrumentation
package main

import (
	"context"
	"crypto/tls"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	"github.com/go-redis/redis/v8"
	"github.com/joho/godotenv"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
)

// Contexto global para o Redis
var ctx = context.Background()

// App struct para injeção de dependência
type App struct {
	RedisClient         *redis.Client
	SqsSvc              *sqs.SQS
	SqsQueueURL         string
	HttpClient          *http.Client
	FlagServiceURL      string
	TargetingServiceURL string
}

func main() {
	_ = godotenv.Load()

	shutdown := initTracer()
	defer func() { _ = shutdown(context.Background()) }()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8004"
	}
	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		log.Fatal("REDIS_URL deve ser definida (ex: redis://localhost:6379)")
	}
	flagSvcURL := os.Getenv("FLAG_SERVICE_URL")
	if flagSvcURL == "" {
		log.Fatal("FLAG_SERVICE_URL deve ser definida")
	}
	targetingSvcURL := os.Getenv("TARGETING_SERVICE_URL")
	if targetingSvcURL == "" {
		log.Fatal("TARGETING_SERVICE_URL deve ser definida")
	}
	sqsQueueURL := os.Getenv("AWS_SQS_URL")
	awsRegion := os.Getenv("AWS_REGION")
	if awsRegion == "" && sqsQueueURL != "" {
		log.Fatal("AWS_REGION deve ser definida para usar SQS")
	}

	var rdb *redis.Client
	if strings.HasPrefix(redisURL, "rediss://") {
		u, err := url.Parse(redisURL)
		if err != nil {
			log.Fatalf("Não foi possível parsear a URL do Redis: %v", err)
		}
		password, _ := u.User.Password()
		rdb = redis.NewClient(&redis.Options{
			Addr:      u.Host,
			Password:  password,
			TLSConfig: &tls.Config{},
		})
	} else {
		opt, err := redis.ParseURL(redisURL)
		if err != nil {
			log.Fatalf("Não foi possível parsear a URL do Redis: %v", err)
		}
		rdb = redis.NewClient(opt)
	}
	if _, err := rdb.Ping(ctx).Result(); err != nil {
		log.Fatalf("Não foi possível conectar ao Redis: %v", err)
	}
	log.Println("Conectado ao Redis com sucesso!")

	var sqsSvc *sqs.SQS
	awsEndpoint := os.Getenv("AWS_ENDPOINT_URL")
	if sqsQueueURL != "" {
		cfg := &aws.Config{Region: aws.String(awsRegion)}
		if awsEndpoint != "" {
			cfg.Endpoint = aws.String(awsEndpoint)
		}
		sess, err := session.NewSession(cfg)
		if err != nil {
			log.Fatalf("Não foi possível criar sessão AWS: %v", err)
		}
		sqsSvc = sqs.New(sess)
		log.Println("Cliente SQS inicializado com sucesso.")
	}

	httpClient := &http.Client{
		Timeout:   5 * time.Second,
		Transport: otelhttp.NewTransport(http.DefaultTransport),
	}

	app := &App{
		RedisClient:         rdb,
		SqsSvc:              sqsSvc,
		SqsQueueURL:         sqsQueueURL,
		HttpClient:          httpClient,
		FlagServiceURL:      flagSvcURL,
		TargetingServiceURL: targetingSvcURL,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)
	mux.HandleFunc("/evaluate", app.evaluationHandler)

	handler := otelhttp.NewHandler(mux, "evaluation-service")
	_ = otel.Tracer("evaluation-service")
	log.Printf("Serviço de Avaliação (Go) rodando na porta %s", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}
