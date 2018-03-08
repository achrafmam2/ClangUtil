struct A {};
struct B {};
int main(void) {
  struct A {
    int data;
    struct A *next;
  };
  int a;
  a = 0;
  struct A my;
  struct B not;
  return 0;
}
