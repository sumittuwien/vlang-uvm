//
//------------------------------------------------------------------------------
//   Copyright 2007-2011 Mentor Graphics Corporation
//   Copyright 2007-2010 Cadence Design Systems, Inc.
//   Copyright 2010 Synopsys, Inc.
//   Copyright 2014 Coverify Systems Technology
//   All Rights Reserved Worldwide
//
//   Licensed under the Apache License, Version 2.0 (the
//   "License"); you may not use this file except in
//   compliance with the License.  You may obtain a copy of
//   the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in
//   writing, software distributed under the License is
//   distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
//   CONDITIONS OF ANY KIND, either express or implied.  See
//   the License for the specific language governing
//   permissions and limitations under the License.
//------------------------------------------------------------------------------

module uvm.tlm1.uvm_tlm_fifos;

// typedef class uvm_tlm_event;
import uvm.tlm1.uvm_tlm_fifo_base;
import uvm.tlm1.uvm_analysis_port;

import uvm.base.uvm_component;
import uvm.base.uvm_object_globals;

import uvm.meta.mailbox;

//------------------------------------------------------------------------------
//
// Title: TLM FIFO Classes
//
// This section defines TLM-based FIFO classes. 
//
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
//
// Class: uvm_tlm_fifo
//
// This class provides storage of transactions between two independently running
// processes. Transactions are put into the FIFO via the ~put_export~. 
// transactions are fetched from the FIFO in the order they arrived via the
// ~get_peek_export~. The ~put_export~ and ~get_peek_export~ are inherited from
// the <uvm_tlm_fifo_base #(T)> super class, and the interface methods provided by
// these exports are defined by the <uvm_tlm_if_base #(T1,T2)> class.
//
//------------------------------------------------------------------------------

class uvm_tlm_fifo(T=int, size_t N=0): uvm_tlm_fifo_base!(T)
{
  enum string type_name = "uvm_tlm_fifo!(T)";

  private mailbox!T m;
  private size_t m_size;

  protected int m_pending_blocked_gets;


  // Function: new
  //
  // The ~name~ and ~parent~ are the normal uvm_component constructor arguments. 
  // The ~parent~ should be null if the <uvm_tlm_fifo> is going to be used in a
  // statically elaborated construct (e.g., a module). The ~size~ indicates the
  // maximum size of the FIFO; a value of zero indicates no upper bound.

  public this(string name=null, uvm_component parent = null, int size = 1) {
    synchronized(this) {
      super(name, parent);
      m = new mailbox!T(size);
      m_size = size;
    }
  }

  override public string get_type_name() {
    return type_name;
  }


  // Function: size
  //
  // Returns the capacity of the FIFO-- that is, the number of entries
  // the FIFO is capable of holding. A return value of 0 indicates the
  // FIFO capacity has no limit.

  override public size_t size() {
    synchronized(this) {
      return m_size;
    }
  }
 

  // Function: used
  //
  // Returns the number of entries put into the FIFO.

  override public size_t used() {
    synchronized(this) {
      return m.num();
    }
  }


  // Function: is_empty
  //
  // Returns 1 when there are no entries in the FIFO, 0 otherwise.

  override public bool is_empty() {
    synchronized(this) {
      return (m.num() is 0);
    }
  }
 

  // Function: is_full
  //
  // Returns 1 when the number of entries in the FIFO is equal to its <size>,
  // 0 otherwise.

  override public bool is_full() {
    synchronized(this) {
      return (m_size !is 0) && (m.num() is m_size);
    }
  }

  // task
  override public void put(T t) {
    mailbox!T _m;
    uvm_analysis_port!(T) _put_ap;
    synchronized(this) {
      _m = m;
      _put_ap = this.put_ap;
    }
    _m.put(t);
    _put_ap.write(t);
  }

  // task
  override public void get(out T t) {
    mailbox!T _m;
    uvm_analysis_port!(T) _get_ap;
    synchronized(this) {
      _m = m;
      _get_ap = this.get_ap;
      m_pending_blocked_gets++;
    }
    _m.get(t);
    synchronized(this) {
      m_pending_blocked_gets--;
    }
    _get_ap.write(t);
  }

  // task
  override public void peek(out T t) {
    mailbox!T _m;
    synchronized(this) {
      _m = m;
    }
    _m.peek(t);
  }
   
  override public bool try_get(out T t) {
    synchronized(this) {
      if(!m.try_get(t)) {
	return false;
      }

      get_ap.write(t);
      return true;
    }
  } 
  
  override public bool try_peek(out T t) {
    synchronized(this) {
      if(!m.try_peek(t)) {
	return false;
      }
      return true;
    }
  }

  override public bool try_put(T t) {
    synchronized(this) {
      if(!m.try_put(t)) {
	return false;
      }
  
      put_ap.write(t);
      return true;
    }
  }  

  override public bool can_put() {
    synchronized(this) {
      return m_size is 0 || m.num() < m_size;
    }
  }  

  override public bool can_get() {
    synchronized(this) {
      return m.num() > 0 && m_pending_blocked_gets == 0;
    }
  }
  
  override public bool can_peek() {
    synchronized(this) {
      return m.num() > 0;
    }
  }


  // Function: flush
  //
  // Removes all entries from the FIFO, after which <used> returns 0
  // and <is_empty> returns 1.

  override public void flush() {
    synchronized(this) {
      T t;
      bool r;

      r = true; 
      while(r) r = try_get(t) ;
    
      if(m.num() > 0 && m_pending_blocked_gets != 0) {
	uvm_report_error("flush failed" ,
			 "there are blocked gets preventing the flush",
			 UVM_NONE);
      }
    }
  }
}


//------------------------------------------------------------------------------
//
// Class: uvm_tlm_analysis_fifo
//
// An analysis_fifo is a <uvm_tlm_fifo> with an unbounded size and a write interface.
// It can be used any place a <uvm_analysis_imp> is used. Typical usage is
// as a buffer between an <uvm_analysis_port> in an initiator component
// and TLM1 target component.
//
//------------------------------------------------------------------------------

class uvm_tlm_analysis_fifo(T=int): uvm_tlm_fifo!T
{

  // Port: analysis_export #(T)
  //
  // The analysis_export provides the write method to all connected analysis
  // ports and parent exports:
  //
  //|  function void write (T t)
  //
  // Access via ports bound to this export is the normal mechanism for writing
  // to an analysis FIFO. 
  // See write method of <uvm_tlm_if_base #(T1,T2)> for more information.

  uvm_analysis_imp!(T, uvm_tlm_analysis_fifo!T) analysis_export;


  // Function: new
  //
  // This is the standard uvm_component constructor. ~name~ is the local name
  // of this component. The ~parent~ should be left unspecified when this
  // component is instantiated in statically elaborated constructs and must be
  // specified when this component is a child of another UVM component.

  public this(string name=null,  uvm_component parent = null) {
    synchronized(this) {
      super(name, parent, 0); // analysis fifo must be unbounded
      analysis_export = new uvm_analysis_imp!(T, uvm_tlm_analysis_fifo!T)("analysis_export", this);
    }
  }

  enum string type_name = "uvm_tlm_analysis_fifo!T";

  public string get_type_name() {
    return type_name;
  }

  public void write(T t) {
    this.try_put(t); // unbounded => must succeed
  }
}
