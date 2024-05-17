# Build isar with Linux ARM64 compatibility
FROM rust AS prebuild
WORKDIR /
RUN apt update
RUN apt install -y libclang-dev
RUN git clone https://github.com/isar/isar.git -b 3.1.0+1
WORKDIR /isar
RUN sh tool/build_linux.sh

# Build the application
FROM dart:3.3.4 AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart run build_runner build --delete-conflicting-outputs
RUN dart compile exe bin/server.dart -o bin/server

# The running application
FROM ubuntu

RUN apt clean
RUN apt-get update
RUN apt-get install -y git gawk

RUN mkdir /app
RUN mkdir /app/bin
COPY --from=build /app/bin/server /app/bin/
COPY --from=prebuild /isar/libisar*.so /app/bin/libisar.so

EXPOSE 8080
CMD ["/app/bin/server", "--conf", "/conf/configuration.json"]
