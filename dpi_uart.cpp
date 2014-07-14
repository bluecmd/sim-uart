#include <fcntl.h>
#include <stdio.h>
#include <termios.h>
#include <unistd.h>

FILE *stream_in;
FILE *stream_out;
char buf;

extern "C" {

void uart_init(void) {
  int flags;
  int fd;

  /* TODO(bluecmd): Allow for files in/out */
  stream_in = stdin;
  stream_out = stdout;

  fd = fileno(stream_in);

  /* change to non-blocking read on input stream */
  flags = fcntl(fd, F_GETFL);
  fcntl(fd, F_SETFL, flags | O_NONBLOCK);

  if (stream_in == stdin) {
    struct termios t;
    /* change to not wait for new line and do not echo */
    tcgetattr(fd, &t);
    t.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(fd, TCSANOW, &t);
  }
}

int uart_tx_is_data_available(void) {
  int ret;
  ret = fread(&buf, 1, 1, stream_in);
  return ret == 1;
}

int uart_tx_get_data(void) {
  return buf;
}

void uart_rx_new_data(char chr) {
  fprintf(stream_out, "%c", chr);
  fflush(stream_out);
}

}
